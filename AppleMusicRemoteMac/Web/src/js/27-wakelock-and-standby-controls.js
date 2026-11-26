  // ==========================================================================
  // Multi-Layer Screen Wake Lock Engine for iPadOS / iOS PWA & Desktop TV Mode
  // Layer 1: W3C Screen Wake Lock API (navigator.wakeLock.request('screen'))
  // Layer 2: Active 2fps <canvas> captureStream -> <video playsinline muted>
  //          (Prevents iPadOS Standalone PWA from auto-locking when no Motion
  //          Cover is playing — works around WebKit Bug #254545)
  // ==========================================================================
  const ScreenWakeLockManager = {
    sentinel: null,
    keepAliveVideo: null,
    keepAliveCanvas: null,
    keepAliveTimer: null,
    tickToggle: false,
    isActive: false,
    lastTouchRearmTs: 0,

    shouldHoldWakeLock() {
      if (!isStandbyOrLandscapeVisible()) return false;
      if (!state.connected) return false;
      const isPlayingOrStarting =
        state.playerState === 'playing' ||
        state.waitingForPlayback ||
        state.isAiCurating ||
        Boolean(state.pendingPlayUntil && Date.now() < state.pendingPlayUntil);
      return isPlayingOrStarting;
    },

    syncByPlaybackAndConnection() {
      if (this.shouldHoldWakeLock()) {
        if (!this.isActive) {
          this.acquire();
        } else {
          this.syncFallbackVideoState();
        }
      } else if (this.isActive) {
        this.release();
      }
    },

    async acquire() {
      if (!this.shouldHoldWakeLock()) {
        this.release();
        return;
      }
      this.isActive = true;
      await this.acquireNativeWakeLock();
      this.syncFallbackVideoState();
    },

    async acquireNativeWakeLock() {
      if (!this.isActive) return;
      if ('wakeLock' in navigator && navigator.wakeLock && typeof navigator.wakeLock.request === 'function') {
        try {
          if (!this.sentinel || this.sentinel.released) {
            const sentinel = await navigator.wakeLock.request('screen');
            if (!this.isActive) {
              try { await sentinel.release(); } catch (_) {}
              return;
            }
            this.sentinel = sentinel;
            this.sentinel.addEventListener('release', () => {
              if (this.isActive && document.visibilityState === 'visible') {
                setTimeout(() => {
                  this.acquireNativeWakeLock().then(() => this.syncFallbackVideoState());
                }, 500);
              }
            });
          }
        } catch (_) {}
      }
    },

    isNativeSentinelHeld() {
      return Boolean(this.sentinel && !this.sentinel.released);
    },

    isStandbyMotionVideoPlaying() {
      const sbVid = document.getElementById('standby-motion-video');
      return Boolean(sbVid && !sbVid.paused && sbVid.classList.contains('visible') && sbVid.currentSrc);
    },

    syncFallbackVideoState() {
      if (!this.isActive) {
        this.stopVideoKeepAlive();
        return;
      }
      // If native W3C Screen Wake Lock is held OR a Motion Cover <video> is actively playing,
      // do NOT waste CPU/GPU running a live canvas.captureStream(2) -> <video> MediaStream pipeline.
      if (this.isNativeSentinelHeld() || this.isStandbyMotionVideoPlaying()) {
        this.stopVideoKeepAlive();
      } else {
        this.startVideoKeepAlive();
      }
    },

    stopVideoKeepAlive(releaseStream = false) {
      if (this.keepAliveTimer) {
        clearInterval(this.keepAliveTimer);
        this.keepAliveTimer = null;
      }
      if (this.keepAliveVideo) {
        if (!this.keepAliveVideo.paused) {
          try {
            this.keepAliveVideo.pause();
          } catch (_) {}
        }
        if (releaseStream && this.keepAliveVideo.srcObject) {
          try {
            const tracks = typeof this.keepAliveVideo.srcObject.getTracks === 'function'
              ? this.keepAliveVideo.srcObject.getTracks()
              : [];
            tracks.forEach((tr) => {
              try { tr.stop(); } catch (_) {}
            });
          } catch (_) {}
          try {
            this.keepAliveVideo.srcObject = null;
          } catch (_) {}
        }
      }
    },

    startVideoKeepAlive() {
      if (!this.isActive) return;
      try {
        if (!this.keepAliveCanvas) {
          const canvas = document.createElement('canvas');
          canvas.width = 16;
          canvas.height = 16;
          this.keepAliveCanvas = canvas;
        }
        const ctx = this.keepAliveCanvas.getContext('2d');
        const drawTick = () => {
          if (!ctx) return;
          this.tickToggle = !this.tickToggle;
          ctx.fillStyle = this.tickToggle ? '#010102' : '#020101';
          ctx.fillRect(0, 0, 16, 16);
        };
        drawTick();

        if (!this.keepAliveTimer) {
          this.keepAliveTimer = setInterval(() => {
            if (!this.isActive) return;
            if (this.isNativeSentinelHeld() || this.isStandbyMotionVideoPlaying()) {
              this.stopVideoKeepAlive();
              return;
            }
            drawTick();
            if (this.keepAliveVideo && this.keepAliveVideo.paused) {
              this.keepAliveVideo.play().catch(() => {});
            }
            if (!this.sentinel || this.sentinel.released) {
              this.acquireNativeWakeLock();
            }
          }, 2000);
        }

        if (!this.keepAliveVideo) {
          const vid = document.createElement('video');
          vid.id = 'standby-wakelock-video';
          vid.muted = true;
          vid.defaultMuted = true;
          vid.loop = true;
          vid.playsInline = true;
          vid.setAttribute('playsinline', '');
          vid.setAttribute('webkit-playsinline', '');
          vid.setAttribute('muted', '');
          // Must have non-zero opacity & size inside the visible viewport so iPadOS WebKit
          // does not cull the video decoder and drop the display sleep assertion
          vid.style.cssText = 'position:fixed;bottom:1px;right:1px;width:2px;height:2px;opacity:0.015;pointer-events:none;z-index:9999;';
          const overlay = document.getElementById('standby-tv-overlay') || document.body;
          overlay.appendChild(vid);
          this.keepAliveVideo = vid;
        }

        if (this.keepAliveVideo && !this.keepAliveVideo.srcObject) {
          const captureFn = this.keepAliveCanvas.captureStream || this.keepAliveCanvas.webkitCaptureStream;
          if (typeof captureFn === 'function') {
            const stream = captureFn.call(this.keepAliveCanvas, 1);
            this.keepAliveVideo.srcObject = stream;
          }
        }

        if (this.keepAliveVideo && this.keepAliveVideo.paused) {
          this.keepAliveVideo.play().catch(() => {});
        }
      } catch (_) {}
    },

    release() {
      this.isActive = false;
      this.stopVideoKeepAlive(true);
      if (this.sentinel) {
        try {
          this.sentinel.release();
        } catch (_) {}
        this.sentinel = null;
      }
    }
  };

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      syncMotionVideoPlaybackState();
      ScreenWakeLockManager.syncByPlaybackAndConnection();
    }
  });

  // Ensure touch/click while TV mode is active re-arms the iPadOS gesture-gated wakeLock when playing (throttled)
  ['touchend', 'click'].forEach((evtName) => {
    document.addEventListener(evtName, () => {
      if (!ScreenWakeLockManager.shouldHoldWakeLock()) return;
      const now = performance.now();
      if (now - ScreenWakeLockManager.lastTouchRearmTs < 3000) return;
      ScreenWakeLockManager.lastTouchRearmTs = now;
      if (!ScreenWakeLockManager.isNativeSentinelHeld()) {
        ScreenWakeLockManager.acquire();
      }
    }, { passive: true });
  });

  function openStandbyMode() {
    if (isMobilePhoneViewport() || window.innerWidth < 768) return;
    const overlay = document.getElementById('standby-tv-overlay');
    if (!overlay) return;
    if (dom.searchInput && document.activeElement === dom.searchInput) {
      dom.searchInput.blur();
    }
    syncKeyboardFocusClass();
    document.body.classList.add('tv-mode-open');
    overlay.classList.remove('hidden');
    overlay.setAttribute('aria-hidden', 'false');
    ScreenWakeLockManager.syncByPlaybackAndConnection();
    try {
      localStorage.setItem('amr_tv_mode_active', '1');
      localStorage.removeItem('amr_default_tv_mode');
    } catch (_) {}
    if (!state.tvLibraryConfigLoaded) {
      send({ action: 'get_tv_library_config' });
    }
    if (!state.playlists || state.playlists.length === 0) {
      send({ action: 'get_playlists' });
    }
    if (!state.libraryAlbums || state.libraryAlbums.length === 0) {
      send({ action: 'get_library_albums' });
    }
    send({ action: 'get_queue' });
    if (typeof syncStandbyQueueBadge === 'function') syncStandbyQueueBadge();
    syncStandbyAndMotionCoverUI();
    syncActiveMotionVideoTarget();
    syncBookletViewerLayoutMode();
    updateScrubberUI(state.lastSyncPos, state.duration);
    ensureScrubberLoopRunning();
    updateStandbyClock();
    refreshAllTitleMarquees(true);
    if (!state.lastDspSettings) {
      send({ action: 'get_dsp_settings' });
    }
    send({ action: 'get_spectral_analysis' });
    syncSpectralPolling();
    const p = document.getElementById('top-settings-popover');
    if (p) {
      blurFocusedInContainer(p);
      p.classList.add('hidden');
      p.setAttribute('aria-hidden', 'true');
    }
  }

  function closeStandbyMode() {
    closeStandbyLibraryModal();
    closeStandbyAiModal();
    if (typeof closeStandbyQueueModal === 'function') closeStandbyQueueModal();
    ScreenWakeLockManager.release();
    document.body.classList.remove('tv-mode-open');
    if (standbyRtaRafId) {
      cancelAnimationFrame(standbyRtaRafId);
      standbyRtaRafId = null;
    }
    const overlay = document.getElementById('standby-tv-overlay');
    if (!overlay) return;
    overlay.classList.add('hidden');
    overlay.setAttribute('aria-hidden', 'true');
    syncActiveMotionVideoTarget();
    syncBookletViewerLayoutMode();
    syncSpectralPolling();
    updateScrubberUI(state.lastSyncPos, state.duration);
    ensureScrubberLoopRunning();
    refreshAllTitleMarquees(true);
    try {
      localStorage.setItem('amr_tv_mode_active', '0');
      localStorage.removeItem('amr_default_tv_mode');
    } catch (_) {}
    const p = document.getElementById('top-settings-popover');
    if (p) {
      blurFocusedInContainer(p);
      p.classList.add('hidden');
      p.setAttribute('aria-hidden', 'true');
    }
  }

  function updateStandbyClock() {
    const el = document.getElementById('standby-clock');
    if (!el) return;
    const now = new Date();
    const hh = String(now.getHours()).padStart(2, '0');
    const mm = String(now.getMinutes()).padStart(2, '0');
    el.textContent = `${hh}:${mm}`;
  }

  function positionSettingsPopoverNearButton(popover, btn) {
    if (!popover || !btn) return;
    const rect = btn.getBoundingClientRect();
    if (!rect || (rect.width === 0 && rect.height === 0)) return;
    const topPos = Math.max(12, Math.min(window.innerHeight - 160, rect.bottom + 8));
    const rightPos = Math.max(12, window.innerWidth - rect.right);
    popover.style.top = `${topPos}px`;
    popover.style.right = `${rightPos}px`;
    popover.style.left = 'auto';
  }

  function setupStandbyAndWledControls() {
    updateStandbyClock();
    setInterval(updateStandbyClock, 15000);

    try {
      const qsStandby = new URLSearchParams(window.location.search || '').get('standby');
      if (qsStandby === '1' || localStorage.getItem('amr_tv_mode_active') === '1') {
        openStandbyMode();
      }
    } catch (_) {}

    const popover = document.getElementById('top-settings-popover');
    let lastSettingsTriggerBtn = null;
    const togglePopover = (e) => {
      if (e) e.stopPropagation();
      if (!popover) return;
      const triggerBtn = e && e.currentTarget ? e.currentTarget : null;
      const isHidden = popover.classList.contains('hidden');
      if (isHidden || (triggerBtn && lastSettingsTriggerBtn !== triggerBtn)) {
        lastSettingsTriggerBtn = triggerBtn;
        send({ action: 'get_wled_settings' });
        popover.classList.remove('hidden');
        popover.setAttribute('aria-hidden', 'false');
        if (triggerBtn) {
          positionSettingsPopoverNearButton(popover, triggerBtn);
        }
      } else {
        blurFocusedInContainer(popover);
        popover.classList.add('hidden');
        popover.setAttribute('aria-hidden', 'true');
      }
    };

    ['btn-top-settings', 'mobile-btn-settings', 'player-btn-settings', 'standby-btn-wled-toggle'].forEach(id => {
      const btn = document.getElementById(id);
      if (btn) btn.addEventListener('click', togglePopover);
    });

    const btnClosePopover = document.getElementById('btn-close-top-settings');
    if (btnClosePopover) {
      btnClosePopover.addEventListener('click', () => {
        if (popover) {
          blurFocusedInContainer(popover);
          popover.classList.add('hidden');
          popover.setAttribute('aria-hidden', 'true');
        }
      });
    }

    document.addEventListener('click', (e) => {
      if (!popover || popover.classList.contains('hidden')) return;
      const insidePopover = popover.contains(e.target);
      const isTrigger = Boolean(e.target.closest('#btn-top-settings, #mobile-btn-settings, #player-btn-settings, #standby-btn-wled-toggle'));
      if (!insidePopover && !isTrigger) {
        blurFocusedInContainer(popover);
        popover.classList.add('hidden');
        popover.setAttribute('aria-hidden', 'true');
      }
    });

    const modeSel = document.getElementById('wled-mode-select');
    if (modeSel) modeSel.addEventListener('change', pushWledSettingsToServer);

    ['btn-standby-mode'].forEach(id => {
      const btn = document.getElementById(id);
      if (btn) btn.addEventListener('click', openStandbyMode);
    });

    const btnCloseStandby = document.getElementById('btn-close-standby');
    if (btnCloseStandby) btnCloseStandby.addEventListener('click', closeStandbyMode);

    const btnStandbyLib = document.getElementById('standby-btn-library');
    if (btnStandbyLib) btnStandbyLib.addEventListener('click', openStandbyLibraryModal);

    const btnCloseStandbyLib = document.getElementById('btn-close-standby-library');
    if (btnCloseStandbyLib) btnCloseStandbyLib.addEventListener('click', closeStandbyLibraryModal);

    const btnStandbyQueue = document.getElementById('standby-btn-queue');
    if (btnStandbyQueue) btnStandbyQueue.addEventListener('click', openStandbyQueueModal);

    const btnCloseStandbyQueue = document.getElementById('btn-close-standby-queue');
    if (btnCloseStandbyQueue) btnCloseStandbyQueue.addEventListener('click', closeStandbyQueueModal);

    const btnStandbyAi = document.getElementById('standby-btn-ai-curator');
    if (btnStandbyAi) btnStandbyAi.addEventListener('click', openStandbyAiModal);

    const btnStandbyAiRefresh = document.getElementById('btn-standby-ai-refresh');
    if (btnStandbyAiRefresh) {
      btnStandbyAiRefresh.addEventListener('click', () => {
        triggerHaptic('light');
        resetAndGenerateStandbyAiTagCloud();
      });
    }

    const btnCloseStandbyAi = document.getElementById('btn-close-standby-ai');
    if (btnCloseStandbyAi) btnCloseStandbyAi.addEventListener('click', closeStandbyAiModal);

    const sbPlayPause = document.getElementById('standby-btn-play-pause');
    const sbPrev = document.getElementById('standby-btn-prev');
    const sbNext = document.getElementById('standby-btn-next');
    const sbFavBtn = document.getElementById('standby-btn-favorite');
    const sbShuffleBtn = document.getElementById('standby-btn-shuffle');
    const sbRepeatBtn = document.getElementById('standby-btn-repeat');
    const sbAiVibeBtn = document.getElementById('standby-btn-ai-track-vibe');
    const sbTrack = document.getElementById('standby-progress-track');

    if (sbPlayPause) sbPlayPause.addEventListener('click', togglePlayPause);
    if (sbPrev) sbPrev.addEventListener('click', () => sendThrottledTransport('previous'));
    if (sbNext) sbNext.addEventListener('click', () => sendThrottledTransport('next'));
    if (sbShuffleBtn) sbShuffleBtn.addEventListener('click', toggleShuffleOptimistic);
    if (sbRepeatBtn) sbRepeatBtn.addEventListener('click', cycleRepeatMode);
    if (sbFavBtn) {
      sbFavBtn.addEventListener('click', handleToggleFavorite);
    }
    if (sbAiVibeBtn) {
      sbAiVibeBtn.addEventListener('click', triggerAiMixFromCurrentTrack);
    }
    const sbProgressInput = document.getElementById('standby-progress-input');
    if (sbProgressInput) {
      sbProgressInput.addEventListener('input', (e) => {
        if (!state.duration || state.duration <= 0) return;
        state.isScrubbing = true;
        const percent = parseFloat(e.target.value);
        const targetPos = (percent / 100) * state.duration;
        state.scrubValue = targetPos;
        const pctStr = `${percent.toFixed(2)}%`;
        const sbFill = document.getElementById('standby-progress-fill');
        const sbThumb = document.getElementById('standby-progress-thumb');
        const sbElapsed = document.getElementById('standby-time-elapsed');
        const sbRem = document.getElementById('standby-time-remaining');
        if (sbFill) sbFill.style.width = pctStr;
        if (sbThumb) sbThumb.style.left = pctStr;
        if (sbElapsed) sbElapsed.textContent = formatTime(targetPos);
        if (sbRem) sbRem.textContent = `-${formatTime(Math.max(0, state.duration - targetPos))}`;
      });
      sbProgressInput.addEventListener('change', commitScrub);
      sbProgressInput.addEventListener('pointerup', commitScrub);
      sbProgressInput.addEventListener('pointercancel', commitScrub);
      sbProgressInput.addEventListener('touchend', commitScrub);
      sbProgressInput.addEventListener('touchcancel', commitScrub);
    } else if (sbTrack) {
      sbTrack.addEventListener('click', (e) => {
        if (!state.duration || state.duration <= 0) return;
        const rect = sbTrack.getBoundingClientRect();
        const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
        sendSeek(ratio * state.duration);
      });
    }

    renderStandbyQuickTiles();

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        if (dom.confirmDeleteModal && !dom.confirmDeleteModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeConfirmDeleteModal();
          return;
        }
        const amrInfoModal = document.getElementById('amr-info-popover');
        if (amrInfoModal && !amrInfoModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          blurFocusedInContainer(amrInfoModal);
          amrInfoModal.classList.add('hidden');
          amrInfoModal.setAttribute('aria-hidden', 'true');
          syncKeyboardFocusClass();
          return;
        }
        if (dom.devicesModal && !dom.devicesModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          blurFocusedInContainer(dom.devicesModal);
          dom.devicesModal.classList.add('hidden');
          dom.devicesModal.setAttribute('aria-hidden', 'true');
          return;
        }
        if (dom.qualityModal && !dom.qualityModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeQualityModal();
          return;
        }
        if (dom.stationPickerModal && !dom.stationPickerModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeStationPickerModal();
          return;
        }
        if (dom.modalAccountDiag && !dom.modalAccountDiag.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          blurFocusedInContainer(dom.modalAccountDiag);
          dom.modalAccountDiag.classList.add('hidden');
          dom.modalAccountDiag.setAttribute('aria-hidden', 'true');
          return;
        }
        const bookletModal = document.getElementById('booklet-viewer-modal');
        if (bookletModal && !bookletModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeBookletViewer();
          return;
        }
        if (popover && !popover.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          blurFocusedInContainer(popover);
          popover.classList.add('hidden');
          popover.setAttribute('aria-hidden', 'true');
          return;
        }
        const aiModal = document.getElementById('standby-ai-modal');
        if (aiModal && !aiModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeStandbyAiModal();
          return;
        }
        const queueModal = document.getElementById('standby-queue-modal');
        if (queueModal && !queueModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeStandbyQueueModal();
          return;
        }
        const libModal = document.getElementById('standby-library-modal');
        if (libModal && !libModal.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeStandbyLibraryModal();
          return;
        }
        const overlay = document.getElementById('standby-tv-overlay');
        if (overlay && !overlay.classList.contains('hidden')) {
          e.stopImmediatePropagation();
          closeStandbyMode();
        }
      }
    });
  }
