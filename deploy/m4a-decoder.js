/*
  Slow Down Buddy: fallback decoder for M4A / MP4 audio, used only when the browser's own decoder refuses a file
  (Safari on iPhone, and so every iPhone browser, can't decode Apple Lossless with Web Audio).

  - Reads the MP4 container itself (sample table of the first audio track).
  - Apple Lossless (ALAC): decoded here in JavaScript. The decoder is a port of Apple's ALAC reference decoder
    (Apache License 2.0, https://github.com/macosforge/alac), informed by the alac.js port by Jens Nockert and
    Devon Govett (Apache License 2.0). See THIRD-PARTY-NOTICES.txt.
  - AAC: handed to WebCodecs' AudioDecoder when the browser has it, otherwise re-wrapped as an ADTS stream, which
    Safari's decoder accepts even when it rejects the MP4 wrapper.
  - Opus (what YouTube downloaders usually save as .m4a): decoded with libopus compiled to WebAssembly
    (opus-decoder, MIT), which the page loads on demand and passes in as options.loadOpus.

  Exposes window.M4ADecoder = { isMP4(bytes), probe(bytes), decode(bytes, ctx, options) }.
*/
(function (root) {
  'use strict';

  // ---------- MP4 container ----------

  const fourcc = (b, o) => String.fromCharCode(b[o], b[o + 1], b[o + 2], b[o + 3]);
  const u16 = (b, o) => (b[o] << 8) | b[o + 1];
  const u32 = (b, o) => ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) >>> 0;

  function isMP4(b) {
    return b.length > 12 && ['ftyp', 'moov', 'mdat', 'free', 'wide', 'skip'].includes(fourcc(b, 4));
  }

  // Iterate the boxes between start and end: yields { type, start (of payload), end }.
  function* boxes(b, start, end) {
    let o = start;
    while (o + 8 <= end) {
      let size = u32(b, o);
      const type = fourcc(b, o + 4);
      let header = 8;
      if (size === 1) { size = u32(b, o + 8) * 4294967296 + u32(b, o + 12); header = 16; }
      else if (size === 0) size = end - o;
      if (size < header || o + size > end) return;
      yield { type, start: o + header, end: o + size };
      o += size;
    }
  }
  const child = (b, box, type) => { for (const c of boxes(b, box.start, box.end)) if (c.type === type) return c; return null; };
  const path = (b, box, ...types) => types.reduce((bx, t) => bx && child(b, bx, t), box);

  // Find the first sound track and read its codec, codec config and the byte range of every sample (packet).
  function probe(b) {
    if (!isMP4(b)) throw new Error('not an MP4/M4A file');
    const top = { start: 0, end: b.length };
    const moov = child(b, top, 'moov');
    if (!moov) throw new Error(child(b, top, 'moof') ? 'streaming-style (fragmented) M4A isn’t supported' : 'the file has no audio track index (it may be incomplete)');
    for (const trak of boxes(b, moov.start, moov.end)) {
      if (trak.type !== 'trak') continue;
      const hdlr = path(b, trak, 'mdia', 'hdlr');
      if (!hdlr || fourcc(b, hdlr.start + 8) !== 'soun') continue;
      const stbl = path(b, trak, 'mdia', 'minf', 'stbl');
      if (!stbl) continue;
      const stsd = child(b, stbl, 'stsd');
      const entry = stsd && boxes(b, stsd.start + 8, stsd.end).next().value;
      if (!entry) continue;
      const codec = entry.type;
      const version = u16(b, entry.start + 8);
      const channels = u16(b, entry.start + 16);
      const sampleRate = u16(b, entry.start + 24); // integer part of the 16.16 rate
      const childStart = entry.start + 28 + (version === 1 ? 16 : version === 2 ? 36 : 0);
      let config = null;
      if (codec === 'alac') {
        const box = child(b, { start: childStart, end: entry.end }, 'alac');
        if (box) config = b.subarray(box.start + 4, box.end); // skip version/flags
      } else if (codec === 'mp4a') {
        let esds = child(b, { start: childStart, end: entry.end }, 'esds');
        if (!esds) { const wave = child(b, { start: childStart, end: entry.end }, 'wave'); esds = wave && child(b, wave, 'esds'); }
        if (esds) config = audioSpecificConfig(b.subarray(esds.start + 4, esds.end));
      } else if (codec === 'Opus') {
        const box = child(b, { start: childStart, end: entry.end }, 'dOps');
        if (box) config = b.subarray(box.start, box.end);
      }
      return { codec, channels, sampleRate, config, samples: sampleTable(b, stbl) };
    }
    throw new Error('no audio track was found');
  }

  function sampleTable(b, stbl) {
    const stsz = child(b, stbl, 'stsz'), stsc = child(b, stbl, 'stsc');
    const stco = child(b, stbl, 'stco'), co64 = child(b, stbl, 'co64');
    if (!stsz || !stsc || !(stco || co64)) throw new Error('the audio track index is incomplete');
    const fixed = u32(b, stsz.start + 4), count = u32(b, stsz.start + 8);
    const sizes = new Uint32Array(count);
    for (let i = 0; i < count; i++) sizes[i] = fixed || u32(b, stsz.start + 12 + i * 4);
    const chunks = [];
    if (stco) { const n = u32(b, stco.start + 4); for (let i = 0; i < n; i++) chunks.push(u32(b, stco.start + 8 + i * 4)); }
    else { const n = u32(b, co64.start + 4); for (let i = 0; i < n; i++) chunks.push(u32(b, co64.start + 8 + i * 8) * 4294967296 + u32(b, co64.start + 12 + i * 8)); }
    const runs = [];
    const nRuns = u32(b, stsc.start + 4);
    for (let i = 0; i < nRuns; i++) runs.push([u32(b, stsc.start + 8 + i * 12) - 1, u32(b, stsc.start + 12 + i * 12)]);
    const offsets = new Float64Array(count);
    let s = 0;
    for (let r = 0; r < runs.length && s < count; r++) {
      const last = r + 1 < runs.length ? runs[r + 1][0] : chunks.length;
      for (let c = runs[r][0]; c < last && s < count; c++) {
        let o = chunks[c];
        for (let k = 0; k < runs[r][1] && s < count; k++) { offsets[s] = o; o += sizes[s]; s++; }
      }
    }
    for (let i = 0; i < count; i++) if (offsets[i] + sizes[i] > b.length) throw new Error('the file is cut short');
    return { count: s, offsets, sizes };
  }

  // esds payload: ES_Descriptor (3) > DecoderConfigDescriptor (4) > DecoderSpecificInfo (5) = AudioSpecificConfig.
  function audioSpecificConfig(d) {
    let o = 0;
    const len = () => { let n = 0, x; do { x = d[o++]; n = (n << 7) | (x & 0x7f); } while (x & 0x80 && o < d.length); return n; };
    while (o < d.length) {
      const tag = d[o++]; const n = len();
      if (tag === 3) { const flags = d[o + 2]; o += 3; if (flags & 0x80) o += 2; if (flags & 0x40) o += 1 + d[o]; if (flags & 0x20) o += 2; }
      else if (tag === 4) o += 13;
      else if (tag === 5) return d.slice(o, o + n);
      else o += n;
    }
    return null;
  }

  // ---------- Apple Lossless ----------

  function alacConfig(c) {
    let o = 0;
    if (c.length >= 12 && fourcc(c, 4) === 'frma') o += 12; // older cookies wrap the config in 'frma' and 'alac' atoms
    if (c.length >= o + 12 && fourcc(c, o + 4) === 'alac') o += 12;
    if (c.length < o + 24) throw new Error('the Apple Lossless settings are missing');
    return {
      frameLength: u32(c, o), bitDepth: c[o + 5], pb: c[o + 6], mb: c[o + 7], kb: c[o + 8],
      numChannels: c[o + 9], maxRun: u16(c, o + 10), sampleRate: u32(c, o + 20),
    };
  }

  // Big-endian bit reader over one packet. read(n) handles n up to 32.
  class Bits {
    constructor(bytes) { this.b = bytes; this.pos = 0; this.end = bytes.length * 8; }
    byte(i) { return i < this.b.length ? this.b[i] : 0; }
    peek32At(pos) { // 32 bits starting at the byte containing pos, shifted left by pos & 7 (as Apple's read32bit does)
      const i = pos >> 3;
      return (((this.byte(i) << 24) | (this.byte(i + 1) << 16) | (this.byte(i + 2) << 8) | this.byte(i + 3)) << (pos & 7)) >>> 0;
    }
    readAt(pos, n) {
      let v = 0;
      for (let i = 0; i < n;) {
        const p = pos + i, inByte = p & 7, take = Math.min(8 - inByte, n - i);
        v = v * (1 << take) + ((this.byte(p >> 3) >> (8 - inByte - take)) & ((1 << take) - 1));
        i += take;
      }
      return v; // unsigned
    }
    read(n) { const v = this.readAt(this.pos, n); this.pos += n; return v; }
    readSigned(n) { const v = this.read(n); return n === 32 ? v | 0 : v >= 2 ** (n - 1) ? v - 2 ** n : v; }
    align() { this.pos = (this.pos + 7) & ~7; }
  }

  const QBSHIFT = 9, QB = 1 << QBSHIFT, MMULSHIFT = 2, MDENSHIFT = QBSHIFT - MMULSHIFT - 1, MOFF = 1 << (MDENSHIFT - 2);
  const BITOFF = 24, MAX_PREFIX_16 = 9, MAX_PREFIX_32 = 9, MAX_DATATYPE_BITS_16 = 16, N_MAX_MEAN_CLAMP = 0xffff;

  function dynGet16(bits, m, k) {
    let pos = bits.pos;
    let stream = bits.peek32At(pos);
    let pre = Math.clz32(~stream >>> 0), result;
    if (pre >= MAX_PREFIX_16) {
      pos += MAX_PREFIX_16;
      result = bits.readAt(pos, MAX_DATATYPE_BITS_16);
      pos += MAX_DATATYPE_BITS_16;
    } else {
      pos += pre + 1;
      const v = bits.readAt(pos, k);
      pos += k;
      result = pre * m + v - 1;
      if (v < 2) { result -= v - 1; pos -= 1; }
    }
    bits.pos = pos;
    return result >>> 0;
  }

  function dynGet32(bits, m, k, maxBits) {
    let pos = bits.pos;
    const stream = bits.peek32At(pos);
    let result = Math.clz32(~stream >>> 0);
    if (result >= MAX_PREFIX_32) {
      result = bits.readAt(pos + MAX_PREFIX_32, maxBits);
      pos += MAX_PREFIX_32 + maxBits;
    } else {
      pos += result + 1;
      if (k !== 1) {
        const v = bits.readAt(pos, k);
        pos += k - 1;
        result *= m;
        if (v >= 2) { result += v - 1; pos += 1; }
      }
    }
    bits.pos = pos;
    return result >>> 0;
  }

  // Adaptive Golomb decode of one channel's residuals into pc.
  function dynDecomp(bits, pc, numSamples, maxSize, mb0, pb, kb, wb) {
    let mb = mb0, zmode = 0, c = 0;
    while (c < numSamples) {
      if (bits.pos >= bits.end) throw new Error('Apple Lossless data ran out');
      let m = mb >>> QBSHIFT;
      let k = Math.min(31 - Math.clz32(m + 3), kb);
      m = (1 << k) - 1;
      let n = dynGet32(bits, m, k, maxSize);
      const nd = (n + zmode) >>> 0;
      pc[c++] = ((nd + 1) >>> 1) * ((-(nd & 1)) | 1);
      mb = (Math.imul(pb, nd) + mb - (Math.imul(pb, mb) >>> QBSHIFT)) >>> 0;
      if (n > N_MAX_MEAN_CLAMP) mb = N_MAX_MEAN_CLAMP;
      zmode = 0;
      if (((mb << MMULSHIFT) >>> 0) < QB && c < numSamples) {
        zmode = 1;
        k = Math.clz32(mb) - BITOFF + ((mb + MOFF) >> MDENSHIFT);
        const mz = ((1 << k) - 1) & wb;
        n = dynGet16(bits, mz, k);
        if (c + n > numSamples) throw new Error('Apple Lossless data is damaged');
        for (let j = 0; j < n; j++) pc[c++] = 0;
        if (n >= 65535) zmode = 0;
        mb = 0;
      }
    }
  }

  const sign = (x) => (x > 0) - (x < 0);

  // Dynamic predictor: rebuild samples from residuals.
  function unpcBlock(pc, out, num, coefs, active, chanBits, denShift) {
    const cs = 32 - chanBits;
    const wrap = (x) => (x << cs) >> cs;
    const denHalf = denShift > 0 ? 1 << (denShift - 1) : 0;
    out[0] = pc[0];
    if (active === 0) { if (out !== pc) for (let j = 1; j < num; j++) out[j] = pc[j]; return; }
    if (active === 31) {
      let prev = out[0];
      for (let j = 1; j < num; j++) { prev = wrap(pc[j] + prev); out[j] = prev; }
      return;
    }
    for (let j = 1; j <= active && j < num; j++) out[j] = wrap(pc[j] + out[j - 1]);
    const lim = active + 1;
    for (let j = lim; j < num; j++) {
      const top = out[j - lim], last = j - 1;
      let sum = 0;
      for (let k = 0; k < active; k++) sum += coefs[k] * (out[last - k] - top);
      let del = pc[j], del0 = del;
      const sg = sign(del);
      del += top + (((sum + denHalf) | 0) >> denShift);
      out[j] = wrap(del);
      if (sg > 0) {
        for (let k = active - 1; k >= 0; k--) {
          const dd = top - out[last - k], sgn = sign(dd);
          coefs[k] -= sgn;
          del0 -= (active - k) * ((sgn * dd) >> denShift);
          if (del0 <= 0) break;
        }
      } else if (sg < 0) {
        for (let k = active - 1; k >= 0; k--) {
          const dd = top - out[last - k], sgn = sign(dd);
          coefs[k] += sgn;
          del0 -= (active - k) * ((-sgn * dd) >> denShift);
          if (del0 >= 0) break;
        }
      }
    }
  }

  // Decode a whole ALAC track into planar Float32 channels (at most two are kept).
  function decodeALAC(b, info) {
    const cfg = alacConfig(info.config);
    if (![16, 20, 24, 32].includes(cfg.bitDepth)) throw new Error(cfg.bitDepth + '-bit Apple Lossless isn’t supported');
    const outChannels = Math.min(2, cfg.numChannels || info.channels || 2);
    const { count, offsets, sizes } = info.samples;
    const maxFrames = count * cfg.frameLength;
    const out = [];
    for (let c = 0; c < outChannels; c++) out.push(new Float32Array(maxFrames));
    const scale = 1 / 2 ** (cfg.bitDepth - 1);
    const mixU = new Int32Array(cfg.frameLength), mixV = new Int32Array(cfg.frameLength);
    const predictor = new Int32Array(cfg.frameLength);
    const shiftBuf = new Uint16Array(cfg.frameLength * 2);
    const coefsU = new Int16Array(32), coefsV = new Int16Array(32);
    let written = 0;

    for (let s = 0; s < count; s++) {
      const bits = new Bits(b.subarray(offsets[s], offsets[s] + sizes[s]));
      let channelIndex = 0, frames = cfg.frameLength;
      for (;;) {
        if (bits.pos + 3 > bits.end) break;
        const tag = bits.read(3);
        if (tag === 7) break; // END
        if (tag === 0 || tag === 3 || tag === 1) { // SCE, LFE, CPE
          const pair = tag === 1, nch = pair ? 2 : 1;
          bits.read(4); // element instance tag
          if (bits.read(12) !== 0) throw new Error('Apple Lossless data is damaged');
          const header = bits.read(4);
          const partial = header >> 3, bytesShifted = (header >> 1) & 3, escape = header & 1;
          if (bytesShifted === 3) throw new Error('Apple Lossless data is damaged');
          if (partial) frames = bits.read(32);
          if (frames > cfg.frameLength) throw new Error('Apple Lossless data is damaged');
          const shift = bytesShifted * 8;
          let mixBits = 0, mixRes = 0;
          if (!escape) {
            const chanBits = cfg.bitDepth - shift + nch - 1;
            mixBits = bits.read(8);
            mixRes = bits.readSigned(8);
            const params = [];
            for (let ch = 0; ch < nch; ch++) {
              const mode = bits.read(4), denShift = bits.read(4), pbFactor = bits.read(3), num = bits.read(5);
              const coefs = ch ? coefsV : coefsU;
              for (let i = 0; i < num; i++) coefs[i] = bits.readSigned(16);
              params.push({ mode, denShift, pbFactor, num, coefs });
            }
            let shiftPos = 0;
            if (bytesShifted) { shiftPos = bits.pos; bits.pos += shift * nch * frames; }
            for (let ch = 0; ch < nch; ch++) {
              const p = params[ch];
              const pb = (cfg.pb * p.pbFactor) >> 2;
              dynDecomp(bits, predictor, frames, chanBits, cfg.mb, pb, cfg.kb, (1 << cfg.kb) - 1);
              const dest = ch ? mixV : mixU;
              if (p.mode === 0) unpcBlock(predictor, dest, frames, p.coefs, p.num, chanBits, p.denShift);
              else {
                unpcBlock(predictor, predictor, frames, null, 31, chanBits, 0);
                unpcBlock(predictor, dest, frames, p.coefs, p.num, chanBits, p.denShift);
              }
            }
            if (bytesShifted) {
              const saved = bits.pos;
              bits.pos = shiftPos;
              for (let i = 0; i < frames * nch; i++) shiftBuf[i] = bits.read(shift);
              bits.pos = saved;
            }
          } else {
            for (let i = 0; i < frames; i++) {
              mixU[i] = bits.readSigned(cfg.bitDepth);
              if (pair) mixV[i] = bits.readSigned(cfg.bitDepth);
            }
          }
          const shifted = !escape && bytesShifted;
          const outU = channelIndex < outChannels ? out[channelIndex] : null;
          const outV = pair && channelIndex + 1 < outChannels ? out[channelIndex + 1] : null;
          for (let i = 0; i < frames; i++) {
            let l, r;
            if (pair) {
              const u = mixU[i], v = mixV[i];
              if (mixRes !== 0) { l = u + v - ((mixRes * v) >> mixBits); r = l - v; } else { l = u; r = v; }
              if (shifted) { l = l * (1 << shift) + shiftBuf[i * 2]; r = r * (1 << shift) + shiftBuf[i * 2 + 1]; }
            } else {
              l = mixU[i];
              if (shifted) l = l * (1 << shift) + shiftBuf[i];
            }
            if (outU) outU[written + i] = l * scale;
            if (outV) outV[written + i] = r * scale;
          }
          channelIndex += nch;
        } else if (tag === 4) { // DSE: skip
          bits.read(4);
          const align = bits.read(1);
          let n = bits.read(8);
          if (n === 255) n += bits.read(8);
          if (align) bits.align();
          bits.pos += n * 8;
        } else if (tag === 6) { // FIL: skip
          let n = bits.read(4);
          if (n === 15) n += bits.read(8) - 1;
          bits.pos += n * 8;
        } else {
          throw new Error('Apple Lossless data uses an unsupported feature');
        }
        if (bits.pos > bits.end) throw new Error('Apple Lossless data is damaged');
      }
      written += frames;
    }
    return { sampleRate: cfg.sampleRate || info.sampleRate, channels: out.map((ch) => ch.subarray(0, written)), length: written };
  }

  // ---------- AAC ----------

  const AAC_RATES = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350];

  function aacParams(asc) {
    let objectType = asc[0] >> 3;
    let rateIndex = ((asc[0] & 7) << 1) | (asc[1] >> 7);
    const channelConfig = (asc[1] >> 3) & 15;
    if (objectType === 31) throw new Error('this AAC type isn’t supported');
    return { objectType, rateIndex, rate: rateIndex < 13 ? AAC_RATES[rateIndex] : 0, channelConfig };
  }

  // Re-wrap the raw AAC packets as ADTS frames (7-byte header each).
  function toADTS(b, info) {
    const p = aacParams(info.config);
    const profile = Math.min(p.objectType, 4) - 1; // ADTS can only signal the basic AAC types; HE-AAC rides as LC
    const chans = p.channelConfig || Math.min(2, info.channels || 2);
    const { count, offsets, sizes } = info.samples;
    let total = 0;
    for (let i = 0; i < count; i++) total += sizes[i] + 7;
    const out = new Uint8Array(total);
    let o = 0;
    for (let i = 0; i < count; i++) {
      const len = sizes[i] + 7;
      out[o] = 0xff; out[o + 1] = 0xf1;
      out[o + 2] = (profile << 6) | (p.rateIndex << 2) | (chans >> 2);
      out[o + 3] = ((chans & 3) << 6) | (len >> 11);
      out[o + 4] = (len >> 3) & 0xff;
      out[o + 5] = ((len & 7) << 5) | 0x1f;
      out[o + 6] = 0xfc;
      out.set(b.subarray(offsets[i], offsets[i] + sizes[i]), o + 7);
      o += len;
    }
    return out;
  }

  async function decodeAACWebCodecs(b, info) {
    const p = aacParams(info.config);
    const codec = 'mp4a.40.' + p.objectType;
    const config = { codec, sampleRate: p.rate || info.sampleRate, numberOfChannels: p.channelConfig || info.channels || 2, description: info.config };
    const support = await AudioDecoder.isConfigSupported(config).catch(() => null);
    if (!support || !support.supported) throw new Error(codec + ' isn’t supported by this browser');
    const parts = [];
    let failure = null, rate = 0, channels = 0, total = 0;
    const decoder = new AudioDecoder({
      output: (data) => {
        rate = data.sampleRate;
        const n = data.numberOfFrames, ch = Math.min(2, data.numberOfChannels);
        channels = Math.max(channels, ch);
        const planes = [];
        for (let c = 0; c < ch; c++) {
          const plane = new Float32Array(n);
          data.copyTo(plane, { planeIndex: c, format: 'f32-planar' });
          planes.push(plane);
        }
        parts.push(planes); total += n;
        data.close();
      },
      error: (e) => { failure = e; },
    });
    decoder.configure(config);
    const { count, offsets, sizes } = info.samples;
    const frameUs = 1024 / config.sampleRate * 1e6;
    for (let i = 0; i < count && !failure; i++) {
      decoder.decode(new EncodedAudioChunk({ type: 'key', timestamp: Math.round(i * frameUs), data: b.subarray(offsets[i], offsets[i] + sizes[i]) }));
      if (decoder.decodeQueueSize > 64) await new Promise((r) => setTimeout(r, 0));
    }
    await decoder.flush().catch((e) => { failure = failure || e; });
    decoder.close();
    if (failure || !total) throw new Error('AAC decoding failed' + (failure && failure.message ? ': ' + failure.message : ''));
    const out = [];
    for (let c = 0; c < channels; c++) {
      const ch = new Float32Array(total);
      let o = 0;
      for (const planes of parts) { ch.set(planes[Math.min(c, planes.length - 1)], o); o += planes[0].length; }
      out.push(ch);
    }
    return { sampleRate: rate, channels: out, length: total };
  }

  // ---------- Opus ----------

  async function decodeOpus(b, info, loadOpus) {
    const d = info.config;
    const channels = d[1], preSkip = u16(d, 2), family = d[10];
    const options = { channels, preSkip, forceStereo: channels > 2 };
    if (family !== 0) {
      options.streamCount = d[11];
      options.coupledStreamCount = d[12];
      options.channelMappingTable = Array.from(d.subarray(13, 13 + channels));
    }
    const lib = await loadOpus();
    const decoder = new lib.OpusDecoder(options);
    try {
      await decoder.ready;
      const { count, offsets, sizes } = info.samples;
      const parts = [];
      let total = 0, outChannels = 0;
      for (let i = 0; i < count; i += 200) {
        const frames = [];
        for (let j = i; j < Math.min(count, i + 200); j++) frames.push(b.subarray(offsets[j], offsets[j] + sizes[j]));
        const r = decoder.decodeFrames(frames);
        if (r.samplesDecoded) {
          outChannels = Math.max(outChannels, Math.min(2, r.channelData.length));
          parts.push(r.channelData.slice(0, 2).map((ch) => ch.slice(0, r.samplesDecoded)));
          total += r.samplesDecoded;
        }
        await new Promise((res) => setTimeout(res, 0)); // keep the page responsive
      }
      if (!total) throw new Error('the Opus decoder found no audio');
      const out = [];
      for (let c = 0; c < outChannels; c++) {
        const ch = new Float32Array(total);
        let o = 0;
        for (const p of parts) { ch.set(p[Math.min(c, p.length - 1)], o); o += p[0].length; }
        out.push(ch);
      }
      return { sampleRate: 48000, channels: out, length: total };
    } finally {
      decoder.free();
    }
  }

  // ---------- entry point ----------

  function nativeDecode(ctx, arrayBuffer) {
    return new Promise((resolve, reject) => {
      const p = ctx.decodeAudioData(arrayBuffer, resolve, (e) => reject(e || new Error('decoding failed')));
      if (p && p.then) p.then(resolve, (e) => reject(e || new Error('decoding failed')));
    });
  }

  // Returns an AudioBuffer at the context's sample rate.
  async function decode(b, ctx, options = {}) {
    const info = probe(b);
    let pcm;
    if (info.codec === 'alac') {
      if (!info.config) throw new Error('the Apple Lossless settings are missing');
      pcm = decodeALAC(b, info);
    } else if (info.codec === 'mp4a') {
      if (!info.config) throw new Error('the AAC settings are missing');
      const errors = [];
      if (typeof AudioDecoder !== 'undefined') {
        try { pcm = await decodeAACWebCodecs(b, info); } catch (e) { errors.push(e && e.message); }
      }
      if (!pcm) {
        try { return await nativeDecode(ctx, toADTS(b, info).buffer); } catch (e) { errors.push((e && e.message) || 'ADTS decoding failed'); }
        throw new Error('this browser couldn’t decode the AAC audio (' + errors.filter(Boolean).join('; ') + ')');
      }
    } else if (info.codec === 'Opus') {
      if (!info.config) throw new Error('the Opus settings are missing');
      if (!options.loadOpus) throw new Error('the Opus decoder isn’t available');
      pcm = await decodeOpus(b, info, options.loadOpus);
    } else {
      throw new Error('the audio codec “' + info.codec.trim() + '” isn’t supported');
    }
    if (!pcm.length) throw new Error('no audio was found');
    const channels = pcm.channels.length;
    const src = new AudioBuffer({ length: pcm.length, numberOfChannels: channels, sampleRate: pcm.sampleRate });
    pcm.channels.forEach((data, c) => src.copyToChannel(data, c));
    if (pcm.sampleRate === ctx.sampleRate) return src;
    const oc = new OfflineAudioContext(channels, Math.ceil((pcm.length * ctx.sampleRate) / pcm.sampleRate), ctx.sampleRate);
    const node = oc.createBufferSource();
    node.buffer = src; node.connect(oc.destination); node.start();
    return oc.startRendering();
  }

  const api = { isMP4, probe, decode, decodeALAC, toADTS };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.M4ADecoder = api;
})(typeof window !== 'undefined' ? window : globalThis);
