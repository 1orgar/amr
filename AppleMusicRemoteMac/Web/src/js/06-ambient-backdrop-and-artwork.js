  // ==========================================================================
  // Apple TV Style Dynamic Blurred Ambient Gradient Background Manager
  // ==========================================================================
  const AmbientBackgroundManager = {
    activeLayer: 'a', // 'a' or 'b'
    currentPaletteKey: '',
    lastRequestedPaletteUrl: '',
    serverPaletteAppliedForUrl: '',
    offscreenCanvas: null,
    offscreenCtx: null,

    init() {
      if (this.offscreenCanvas) return;
      this.offscreenCanvas = document.createElement('canvas');
      this.offscreenCanvas.width = 32;
      this.offscreenCanvas.height = 32;
      this.offscreenCtx = this.offscreenCanvas.getContext('2d', { willReadFrequently: true });
    },

    rgbToHsv(r, g, b) {
      const rf = r / 255;
      const gf = g / 255;
      const bf = b / 255;
      const max = Math.max(rf, gf, bf);
      const min = Math.min(rf, gf, bf);
      const d = max - min;
      let h = 0;
      if (d > 0.0001) {
        if (max === rf) h = 60 * (((gf - bf) / d) % 6);
        else if (max === gf) h = 60 * ((bf - rf) / d + 2);
        else h = 60 * ((rf - gf) / d + 4);
        if (h < 0) h += 360;
      }
      const s = max <= 0.0001 ? 0 : d / max;
      return { h, s, v: max };
    },

    hsvToRgb(h, s, v) {
      const cleanH = ((h % 360) + 360) % 360;
      const c = v * s;
      const x = c * (1 - Math.abs(((cleanH / 60) % 2) - 1));
      const m = v - c;
      let r1 = 0, g1 = 0, b1 = 0;
      if (cleanH < 60) { r1 = c; g1 = x; }
      else if (cleanH < 120) { r1 = x; g1 = c; }
      else if (cleanH < 180) { g1 = c; b1 = x; }
      else if (cleanH < 240) { g1 = x; b1 = c; }
      else if (cleanH < 300) { r1 = x; b1 = c; }
      else { r1 = c; b1 = x; }
      return [
        Math.round((r1 + m) * 255),
        Math.round((g1 + m) * 255),
        Math.round((b1 + m) * 255)
      ];
    },

    hueDistance(h1, h2) {
      const diff = Math.abs(h1 - h2) % 360;
      return diff > 180 ? 360 - diff : diff;
    },

    // Extract 16 spatial perimeter zones + distinct chromatic clusters for WLED DDP
    extractWledZones(img) {
      this.init();
      const ctx = this.offscreenCtx;
      if (!ctx) return [[250, 35, 59], [121, 40, 202], [28, 140, 220], [255, 107, 139]];

      try {
        ctx.clearRect(0, 0, 32, 32);
        ctx.drawImage(img, 0, 0, 32, 32);
        const imgData = ctx.getImageData(0, 0, 32, 32).data;

        // 1. Collect distinct chromatic accent clusters across the whole cover
        const candidates = [];
        for (let i = 0; i < imgData.length; i += 16) {
          const r = imgData[i], g = imgData[i + 1], b = imgData[i + 2], a = imgData[i + 3];
          if (a < 128) continue;
          const hsv = this.rgbToHsv(r, g, b);
          if (hsv.v < 0.08) continue;
          const score = Math.pow(hsv.s, 0.7) * Math.pow(hsv.v, 0.5);
          candidates.push({ r, g, b, h: hsv.h, s: hsv.s, v: hsv.v, score });
        }
        candidates.sort((a, b) => b.score - a.score);

        const distinctAccents = [];
        for (const c of candidates) {
          if (distinctAccents.length >= 6) break;
          if (distinctAccents.every(ex => this.hueDistance(ex.h, c.h) >= 32)) {
            distinctAccents.push(c);
          }
        }
        if (distinctAccents.length === 0 && candidates.length > 0) {
          distinctAccents.push(candidates[0]);
        }

        // 2. Sample 16 spatial perimeter boxes around the 32x32 cover:
        // 0..3: Left edge (bottom -> top)
        // 4..11: Top edge (left -> right)
        // 12..15: Right edge (top -> bottom)
        const boxes = [
          [0, 24, 6, 8], [0, 16, 6, 8], [0, 8, 6, 8], [0, 0, 6, 8],
          [0, 0, 4, 6], [4, 0, 4, 6], [8, 0, 4, 6], [12, 0, 4, 6],
          [16, 0, 4, 6], [20, 0, 4, 6], [24, 0, 4, 6], [28, 0, 4, 6],
          [26, 0, 6, 8], [26, 8, 6, 8], [26, 16, 6, 8], [26, 24, 6, 8]
        ];

        const zones = [];
        for (let z = 0; z < boxes.length; z++) {
          const [bx, by, bw, bh] = boxes[z];
          let bestSample = null;
          let sumR = 0, sumG = 0, sumB = 0, count = 0;

          for (let y = by; y < by + bh; y++) {
            for (let x = bx; x < bx + bw; x++) {
              const idx = (y * 32 + x) * 4;
              const r = imgData[idx], g = imgData[idx + 1], b = imgData[idx + 2];
              sumR += r; sumG += g; sumB += b; count++;
              const hsv = this.rgbToHsv(r, g, b);
              const score = hsv.s * 1.4 + hsv.v * 0.6;
              if (!bestSample || score > bestSample.score) {
                bestSample = { r, g, b, h: hsv.h, s: hsv.s, v: hsv.v, score };
              }
            }
          }

          let chosen = bestSample || {
            r: Math.round(sumR / Math.max(1, count)),
            g: Math.round(sumG / Math.max(1, count)),
            b: Math.round(sumB / Math.max(1, count)),
            ...this.rgbToHsv(sumR / Math.max(1, count), sumG / Math.max(1, count), sumB / Math.max(1, count))
          };

          // If this perimeter zone is dull/monotonous and we have distinct cover accents, weave them in!
          if ((chosen.s < 0.25 || z % 3 === 1) && distinctAccents.length > 1) {
            const acc = distinctAccents[z % distinctAccents.length];
            chosen = { ...acc };
          }

          const boostedS = chosen.s < 0.08 ? 0.85 : Math.min(1.0, Math.pow(chosen.s, 0.45) * 1.2);
          const boostedV = Math.min(1.0, Math.max(0.32, Math.pow(chosen.v, 0.8) * 1.15));
          zones.push(this.hsvToRgb(chosen.h, boostedS, boostedV));
        }

        return zones;
      } catch (e) {
        return [[250, 35, 59], [121, 40, 202], [28, 140, 220], [255, 107, 139]];
      }
    },

    // Extract 4 harmonic ambient colors from image
    extractPalette(img) {
      this.init();
      const ctx = this.offscreenCtx;
      if (!ctx) return this.getDefaultPalette();

      try {
        ctx.clearRect(0, 0, 32, 32);
        ctx.drawImage(img, 0, 0, 32, 32);
        const imgData = ctx.getImageData(0, 0, 32, 32).data;
        const colorSamples = [];

        for (let i = 0; i < imgData.length; i += 16) { // sample every 4th pixel
          const r = imgData[i];
          const g = imgData[i + 1];
          const b = imgData[i + 2];
          const a = imgData[i + 3];

          if (a < 128) continue;

          const max = Math.max(r, g, b) / 255;
          const min = Math.min(r, g, b) / 255;
          const lum = (max + min) / 2;

          // Skip pure black or blown out highlights for ambient background
          if (lum < 0.06 || lum > 0.94) continue;

          const delta = max - min;
          const sat = delta === 0 ? 0 : delta / (1 - Math.abs(2 * lum - 1));
          const hsv = this.rgbToHsv(r, g, b);

          colorSamples.push({ r, g, b, sat, lum, h: hsv.h });
        }

        if (colorSamples.length === 0) {
          return this.getDefaultPalette();
        }

        // Sort by saturation to prioritize vivid, rich hues
        colorSamples.sort((c1, c2) => c2.sat - c1.sat);

        // Pick 4 chromatically distinct colors when available
        const picked = [colorSamples[0]];
        for (const sample of colorSamples) {
          if (picked.length >= 4) break;
          if (picked.every(p => this.hueDistance(p.h, sample.h) >= 28)) {
            picked.push(sample);
          }
        }
        const vibrant = picked[0];
        const secondary = picked[1] || colorSamples[Math.floor(colorSamples.length * 0.35)] || vibrant;
        const tertiary = picked[2] || colorSamples[Math.floor(colorSamples.length * 0.70)] || secondary;
        const deep = picked[3] || colorSamples[colorSamples.length - 1] || tertiary;

        return [
          this.tuneColor(vibrant, 1.5, 0.52),
          this.tuneColor(secondary, 1.4, 0.46),
          this.tuneColor(tertiary, 1.35, 0.48),
          this.tuneColor(deep, 1.25, 0.36)
        ];
      } catch (err) {
        // Fallback for tainted canvas
        return this.getDefaultPalette();
      }
    },

    tuneColor(col, satMultiplier, targetLum) {
      let r = col.r;
      let g = col.g;
      let b = col.b;

      // Adjust brightness toward targetLum
      const currentLum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
      const factor = currentLum > 0 ? targetLum / currentLum : 1.0;
      r = Math.min(255, Math.max(16, Math.round(r * factor)));
      g = Math.min(255, Math.max(16, Math.round(g * factor)));
      b = Math.min(255, Math.max(16, Math.round(b * factor)));

      // Boost saturation
      const avg = (r + g + b) / 3;
      r = Math.min(255, Math.max(0, Math.round(avg + (r - avg) * satMultiplier)));
      g = Math.min(255, Math.max(0, Math.round(avg + (g - avg) * satMultiplier)));
      b = Math.min(255, Math.max(0, Math.round(avg + (b - avg) * satMultiplier)));

      return `rgba(${r}, ${g}, ${b}, 0.85)`;
    },

    getDefaultPalette() {
      return [
        'rgba(50, 30, 85, 0.65)',
        'rgba(30, 55, 105, 0.60)',
        'rgba(75, 35, 65, 0.55)',
        'rgba(25, 70, 90, 0.50)'
      ];
    },

    updateFromImage(img, artUrl) {
      if (!dom.ambientBackdrop) return;
      if (!artUrl || artUrl === 'apple-touch-icon.svg') {
        this.clear();
        return;
      }

      // Request Apple Neural Engine Vision Saliency palette at most ONCE per artwork URL
      if (state.aiCuratorEnabled && this.lastRequestedPaletteUrl !== artUrl) {
        this.lastRequestedPaletteUrl = artUrl;
        send({
          action: 'get_artwork_palette',
          params: {
            url: artUrl,
            track_id: Number(state.currentTrackId || 0) || 0
          }
        });
      }

      // Do not overwrite an already-applied Vision ANE palette for this exact cover URL
      if (this.serverPaletteAppliedForUrl === artUrl) {
        return;
      }

      const palette = this.extractPalette(img);
      const paletteKey = palette.join('|');
      if (paletteKey === this.currentPaletteKey) return;
      this.currentPaletteKey = paletteKey;

      // Dual buffer swap: 'a' <-> 'b'
      const nextLayer = this.activeLayer === 'a' ? 'b' : 'a';
      const targetElem = nextLayer === 'a' ? dom.ambientLayerA : dom.ambientLayerB;
      const prevElem = this.activeLayer === 'a' ? dom.ambientLayerA : dom.ambientLayerB;

      if (targetElem) {
        targetElem.style.setProperty('--blob-1', palette[0]);
        targetElem.style.setProperty('--blob-2', palette[1]);
        targetElem.style.setProperty('--blob-3', palette[2]);
        targetElem.style.setProperty('--blob-4', palette[3]);

        targetElem.classList.add('visible');
      }

      if (prevElem) {
        prevElem.classList.remove('visible');
      }

      this.activeLayer = nextLayer;
      dom.ambientBackdrop.classList.add('active');

      // Extract 16 spatial perimeter zones for WLED DDP Ambilight ONLY when WLED is enabled
      const rgbColors = palette.map((rgbaStr) => {
        const m = rgbaStr.match(/(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
        return m ? [parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10)] : [250, 35, 59];
      });
      // Only send fallback client-canvas WLED zones when Mac Vision Neural Engine palette is disabled;
      // otherwise Mac server authoritatively applies the Vision Saliency cover palette without dual-source flicker.
      if (state.wledEnabled && !state.aiCuratorEnabled) {
        const wledZones = this.extractWledZones(img);
        send({
          action: 'update_wled_palette',
          params: { colors: wledZones.length >= 4 ? wledZones : rgbColors }
        });
      }
      const standbyBg = document.getElementById('standby-ambient-bg');
      if (standbyBg && rgbColors.length >= 3) {
        this.applyStandbyAmbientColors(rgbColors);
      }
    },

    lastStandbyBgKey: '',
    applyStandbyAmbientColors(rgbColors) {
      const standbyBg = document.getElementById('standby-ambient-bg');
      if (!standbyBg || !Array.isArray(rgbColors) || rgbColors.length < 3) return;
      const [c0, c1, c2] = rgbColors;
      const bgKey = `${c0[0]},${c0[1]},${c0[2]}|${c1[0]},${c1[1]},${c1[2]}|${c2[0]},${c2[1]},${c2[2]}`;
      if (bgKey === this.lastStandbyBgKey) return;
      this.lastStandbyBgKey = bgKey;
      standbyBg.style.background = `
        radial-gradient(circle at 24% 48%, rgba(${c0[0]}, ${c0[1]}, ${c0[2]}, 0.38), transparent 62%),
        radial-gradient(circle at 78% 32%, rgba(${c1[0]}, ${c1[1]}, ${c1[2]}, 0.30), transparent 65%),
        radial-gradient(circle at 60% 82%, rgba(${c2[0]}, ${c2[1]}, ${c2[2]}, 0.24), transparent 68%),
        #040406
      `;
      const rtaBackdrop = document.getElementById('standby-rta-backdrop');
      if (rtaBackdrop) {
        const br = Math.min(255, Math.round(c0[0] * 0.65 + 110));
        const bg = Math.min(255, Math.round(c0[1] * 0.65 + 110));
        const bb = Math.min(255, Math.round(c0[2] * 0.65 + 110));
        rtaBackdrop.style.setProperty('--rta-bar-rgb', `${br}, ${bg}, ${bb}`);
      }
    },

    applyServerPalette(data) {
      if (!data || data.status !== 'ok' || !Array.isArray(data.ambient_rgb) || data.ambient_rgb.length < 3) {
        return;
      }
      if (!dom.ambientBackdrop) return;
      const rgbList = data.ambient_rgb.map((arr) => [
        Math.max(0, Math.min(255, Number(arr[0]) || 30)),
        Math.max(0, Math.min(255, Number(arr[1]) || 30)),
        Math.max(0, Math.min(255, Number(arr[2]) || 45))
      ]);
      while (rgbList.length < 4) {
        rgbList.push(rgbList[rgbList.length - 1]);
      }

      const tunedBlobs = [
        this.tuneColor({ r: rgbList[0][0], g: rgbList[0][1], b: rgbList[0][2] }, 1.35, 0.42),
        this.tuneColor({ r: rgbList[1][0], g: rgbList[1][1], b: rgbList[1][2] }, 1.25, 0.36),
        this.tuneColor({ r: rgbList[2][0], g: rgbList[2][1], b: rgbList[2][2] }, 1.30, 0.38),
        this.tuneColor({ r: rgbList[3][0], g: rgbList[3][1], b: rgbList[3][2] }, 1.20, 0.32)
      ];
      const serverKey = 'vision|' + tunedBlobs.join('|');
      this.serverPaletteAppliedForUrl = this.lastRequestedPaletteUrl || currentLoadedArtworkUrl || '';
      if (serverKey === this.currentPaletteKey) return;
      this.currentPaletteKey = serverKey;

      const nextLayer = this.activeLayer === 'a' ? 'b' : 'a';
      const targetElem = nextLayer === 'a' ? dom.ambientLayerA : dom.ambientLayerB;
      const prevElem = this.activeLayer === 'a' ? dom.ambientLayerA : dom.ambientLayerB;

      if (targetElem) {
        targetElem.style.setProperty('--blob-1', tunedBlobs[0]);
        targetElem.style.setProperty('--blob-2', tunedBlobs[1]);
        targetElem.style.setProperty('--blob-3', tunedBlobs[2]);
        targetElem.style.setProperty('--blob-4', tunedBlobs[3]);
        targetElem.classList.add('visible');
      }
      if (prevElem) {
        prevElem.classList.remove('visible');
      }
      this.activeLayer = nextLayer;
      dom.ambientBackdrop.classList.add('active');

      this.applyStandbyAmbientColors(rgbList);
    },

    clear() {
      if (!dom.ambientBackdrop) return;
      dom.ambientBackdrop.classList.remove('active');
      if (dom.ambientLayerA) dom.ambientLayerA.classList.remove('visible');
      if (dom.ambientLayerB) dom.ambientLayerB.classList.remove('visible');
      this.currentPaletteKey = '';
      this.lastRequestedPaletteUrl = '';
      this.serverPaletteAppliedForUrl = '';
    }
  };

  let currentLoadedArtworkUrl = '';
  function setPlayerArtwork(artUrl) {
    artUrl = artUrl ? appendDeviceIdToUrl(artUrl) : 'apple-touch-icon.svg';
    if (dom.playerArtwork.dataset.targetSrc === artUrl) {
      return;
    }
    dom.playerArtwork.dataset.targetSrc = artUrl;

    if (artUrl === 'apple-touch-icon.svg') {
      dom.playerArtwork.src = artUrl;
      dom.playerArtwork.style.opacity = '1';
      currentLoadedArtworkUrl = artUrl;
      if (dom.miniArt) {
        dom.miniArt.src = artUrl;
        dom.miniArt.style.opacity = '1';
      }
      AmbientBackgroundManager.clear();
      return;
    }

    // Immediately dim/fade the artwork elements so the old track's image NEVER lingers
    if (currentLoadedArtworkUrl && currentLoadedArtworkUrl !== artUrl) {
      dom.playerArtwork.style.opacity = '0';
      if (dom.miniArt) dom.miniArt.style.opacity = '0.3';
    }

    const applyLoadedImage = (loadedImg) => {
      if (dom.playerArtwork.dataset.targetSrc !== artUrl) return;
      dom.playerArtwork.src = artUrl;
      dom.playerArtwork.style.opacity = '1';
      currentLoadedArtworkUrl = artUrl;
      if (dom.miniArt) {
        dom.miniArt.src = artUrl;
        dom.miniArt.style.opacity = '1';
      }
      AmbientBackgroundManager.updateFromImage(loadedImg, artUrl);
    };

    const applyFallbackIcon = () => {
      if (dom.playerArtwork.dataset.targetSrc !== artUrl) return;
      dom.playerArtwork.src = 'apple-touch-icon.svg';
      dom.playerArtwork.style.opacity = '1';
      currentLoadedArtworkUrl = 'apple-touch-icon.svg';
      if (dom.miniArt) {
        dom.miniArt.src = 'apple-touch-icon.svg';
        dom.miniArt.style.opacity = '1';
      }
      AmbientBackgroundManager.clear();
    };

    // Only set crossOrigin='anonymous' for external http(s) URLs when client-side canvas readback is needed;
    // same-origin /api/artwork/... images are already non-tainted and omit CORS mode so cookies & auth work reliably.
    const isExternalHttp = /^https?:\/\//i.test(artUrl) && !artUrl.startsWith(window.location.origin);
    const useCors = isExternalHttp && (!state.aiCuratorEnabled || state.wledEnabled);

    const img = new Image();
    if (useCors) {
      img.crossOrigin = 'anonymous';
    }
    img.onload = () => applyLoadedImage(img);
    img.onerror = () => {
      // If Safari/WebKit cached a non-CORS response from a queue/standby <img>, retry once without crossOrigin
      if (useCors) {
        const retryImg = new Image();
        retryImg.onload = () => applyLoadedImage(retryImg);
        retryImg.onerror = applyFallbackIcon;
        retryImg.src = artUrl;
        return;
      }
      applyFallbackIcon();
    };
    img.src = artUrl;
  }

  let marqueeRafId = 0;

  function updateSingleTitleMarquee(el, forceRecalc = false) {
    if (!el) return;
    const text = el.textContent || '';
    if (!forceRecalc && el.dataset.marqueeText === text) {
      return;
    }
    const viewport = el.closest('.title-marquee-viewport') || el.parentElement;
    if (!viewport) return;

    const viewportWidth = Math.floor(viewport.clientWidth);
    if (viewportWidth <= 0) return;

    const sig = `${text}|${viewportWidth}`;
    if (!forceRecalc && el.dataset.marqueeSig === sig) {
      el.dataset.marqueeText = text;
      return;
    }
    el.dataset.marqueeSig = sig;
    el.dataset.marqueeText = text;

    el.classList.remove('is-marquee');
    viewport.classList.remove('is-marquee');
    el.style.removeProperty('--marquee-distance');
    el.style.removeProperty('--marquee-duration');

    // Measure true unconstrained single-line width across all browsers (including WebKit/Safari)
    el.style.display = 'inline-block';
    el.style.width = 'max-content';
    el.style.maxWidth = 'none';
    el.style.overflow = 'visible';
    el.style.textOverflow = 'clip';
    const textWidth = Math.ceil(el.getBoundingClientRect().width);
    el.style.display = '';
    el.style.width = '';
    el.style.maxWidth = '';
    el.style.overflow = '';
    el.style.textOverflow = '';

    const overflow = Math.ceil(textWidth - viewportWidth);

    if (overflow > 2) {
      // Extra padding so the last character clears the right-edge gradient mask completely
      const rightPad = Math.max(20, Math.round(viewportWidth * 0.055));
      const distance = -(overflow + rightPad);
      const duration = Math.max(7.0, Math.min(20.0, (Math.abs(distance) / 36) + 3.6));
      el.style.setProperty('--marquee-distance', `${distance}px`);
      el.style.setProperty('--marquee-duration', `${duration.toFixed(1)}s`);
      el.classList.add('is-marquee');
      viewport.classList.add('is-marquee');
    }
  }

  function refreshAllTitleMarquees(forceRecalc = false) {
    if (marqueeRafId) cancelAnimationFrame(marqueeRafId);
    marqueeRafId = requestAnimationFrame(() => {
      marqueeRafId = 0;
      const force = Boolean(forceRecalc === true);
      updateSingleTitleMarquee(dom.playerTitle, force);
      updateSingleTitleMarquee(dom.miniTitle, force);
      updateSingleTitleMarquee(document.getElementById('standby-title'), force);
    });
  }

  window.addEventListener('resize', () => refreshAllTitleMarquees(true));
  window.addEventListener('orientationchange', () => {
    setTimeout(() => refreshAllTitleMarquees(true), 120);
  });
