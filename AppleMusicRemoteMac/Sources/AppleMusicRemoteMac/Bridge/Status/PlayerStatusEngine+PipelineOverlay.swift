//
//  PlayerStatusEngine+PipelineOverlay.swift
//  AppleMusicRemoteMac
//
//  Live DSP, Room EQ, Late-Night DRC, Mastering Restoration, Spectral, and SoundCheck overlay.
//

import Foundation

extension PlayerStatusEngine {

    @discardableResult
    internal func applyLiveAudioPipelineOverlay(
        to status: inout PlayerStatus,
        updateTapFormatIfNeeded: Bool
    ) -> (isLosslessQuality: Bool, activeSourceRate: Double?, activeSourceDepth: Int?, baseDeviceRate: Double) {
        status.isDucked = AudioDuckingController.shared.isDucked
        status.isVolumeLockedTo100 = PlaybackStateStore.shared.isVolumeLockedTo100

        let ampCtrl = ExternalAmpTCPController.shared
        let ampActive = ampCtrl.isActive
        status.ampVolumeControlEnabled = ampActive
        if ampActive {
            status.ampBrandName = ampCtrl.profile.displayName
            status.ampVolume = ampCtrl.currentVolume
            status.ampMaxVolume = ampCtrl.maxVolumeCap
            status.ampMuted = ampCtrl.isMuted
            status.ampConnected = ampCtrl.isConnected
            status.ampSoundCheckEnabled = ampCtrl.isSoundCheckEnabled
            status.ampLowVolSmartNormEnabled = ampCtrl.isLowVolumeSmartNormEnabled
            status.ampSoundCheckGainDb = ampCtrl.currentTrackGainDb
            status.ampSoundCheckOffset = ampCtrl.currentTrackVolumeOffset
            status.ampBaseVolume = ampCtrl.baseListeningVolume
            status.volume = ampCtrl.currentVolume
        } else {
            status.ampBrandName = nil
            status.ampVolume = nil
            status.ampMaxVolume = nil
            status.ampMuted = nil
            status.ampConnected = nil
            status.ampSoundCheckEnabled = nil
            status.ampLowVolSmartNormEnabled = nil
            status.ampSoundCheckGainDb = nil
            status.ampSoundCheckOffset = nil
            status.ampBaseVolume = nil
        }

        let isPendingOrLossy = status.audioQuality.contains("AAC")
            || status.audioQuality.contains("MP3")
            || status.audioQuality.contains("Буферизация")
            || status.audioQuality.contains("Ожидание CDN")
            || status.audioQuality.contains("Определение")
        let isLosslessQuality = !isPendingOrLossy
        let activeSourceRate = status.track?.sampleRate.map { Double($0) }
            ?? (isLosslessQuality ? BitPerfectLogMonitor.shared.currentDetectedSampleRate : 44100.0)
        let activeSourceDepth = !isLosslessQuality
            ? 16
            : (status.track?.bitDepth ?? BitPerfectLogMonitor.shared.currentDetectedBitDepth)

        let activeDLNA = DLNADiscoveryManager.shared.getActiveRenderer()
        let hasActiveDLNA = (activeDLNA != nil)
        if let dlna = activeDLNA {
            status.isDlnaActive = true
            if !ampActive {
                status.volume = status.isVolumeLockedTo100 ? 100 : DLNADiscoveryManager.shared.currentVolume
            }
            if updateTapFormatIfNeeded, let trRate = status.track?.sampleRate, trRate > 0, BitPerfectLogMonitor.shared.isEnabled {
                let trDepth = !isLosslessQuality ? 16 : (status.track?.bitDepth ?? (trRate >= 48000 ? 24 : 16))
                if AudioProcessTapService.shared.sampleRate != trRate || AudioProcessTapService.shared.bitDepth != trDepth {
                    AudioProcessTapService.shared.setFormat(sampleRate: trRate, bitDepth: trDepth)
                }
            }
            status.audioDeviceName = dlna.friendlyName
            status.audioDeviceSampleRate = Double(AudioProcessTapService.shared.sampleRate)
            status.audioDeviceBitDepth = AudioProcessTapService.shared.bitDepth
        } else {
            status.isDlnaActive = false
            if let defDevice = CoreAudioDeviceManager.shared.getDefaultOutputDevice() {
                status.audioDeviceName = defDevice.name
                status.audioDeviceSampleRate = defDevice.currentSampleRate
                status.audioDeviceBitDepth = activeSourceDepth ?? (defDevice.currentSampleRate >= 48000.0 ? 24 : 16)
            }
        }

        let roomProf = RoomAcousticService.shared.activeProfile
        let isRoomEQActive = RoomAcousticService.shared.isCorrectionEnabled && roomProf != nil
        status.roomCorrectionActive = isRoomEQActive
        status.roomProfileName = isRoomEQActive ? roomProf?.name : nil

        let drcSvc = LateNightDRCService.shared
        let drcMode = drcSvc.mode
        status.lateNightDrcMode = drcMode.rawValue
        status.lateNightDrcEnabled = drcSvc.isEnabled
        status.lateNightDrcProfile = drcSvc.selectedProfile.rawValue
        status.lateNightDrcGainDb = drcMode.isEnabled ? drcSvc.activeGainDB() : 0.0

        let mrSvc = MasteringRestorationService.shared
        let dcMode = mrSvc.deClipMode
        let deMode = mrSvc.deEsserMode
        let mrSnap = mrSvc.activeTelemetrySnapshot()
        status.masteringDeclipMode = dcMode.rawValue
        status.masteringDeclipRestoredDb = dcMode.isEnabled ? ((mrSnap.restoredPeakDB * 10.0).rounded() / 10.0) : 0.0
        status.masteringDeesserMode = deMode.rawValue
        status.masteringDeesserGainDb = deMode.isEnabled ? ((mrSnap.deEsserGainReductionDB * 10.0).rounded() / 10.0) : 0.0

        let isPreDSPModifyingAudio = isRoomEQActive || drcMode.isEnabled || mrSvc.isAnyEnabled

        let baseDeviceRate = status.audioDeviceSampleRate ?? 44100.0
        let ratesMatch = (activeSourceRate == nil) || (abs((activeSourceRate ?? baseDeviceRate) - baseDeviceRate) <= 500.0)
        status.isBitPerfect = BitPerfectLogMonitor.shared.isEnabled
            && isLosslessQuality
            && ratesMatch
            && !isPreDSPModifyingAudio
        status.isDacMutingGuardEnabled = CoreAudioDeviceManager.shared.isMutingGuardEnabled
        status.dacMutingGuardMs = CoreAudioDeviceManager.shared.mutingGuardDurationMs

        let dspConfig = AudioEngineController.shared.currentConfigurationSnapshot()
        let dspTelemetry = AudioEngineController.shared.latestTelemetrySnapshot()
        let isDspRunning = !hasActiveDLNA && dspTelemetry.isRunning
        status.dspMode = isDspRunning ? dspTelemetry.activeMode.rawValue : DSPEngineMode.bitPerfectPassthrough.rawValue
        let profileDisplayName: String = {
            switch dspConfig.profile {
            case .transient: return "7EC-Transient"
            case .balanced: return "7EC-Balanced"
            case .superWide: return "7EC-Super"
            }
        }()
        status.dspProfile = profileDisplayName
        status.dspOutputSampleRate = isDspRunning ? dspTelemetry.outputSampleRateHz : 0
        status.dspDoPCarrierRate = isDspRunning ? dspTelemetry.dopCarrierRateHz : 0
        status.dspIsHogMode = isDspRunning && dspTelemetry.isHogModeActive
        status.dspIsIntegerMode = isDspRunning && dspTelemetry.isIntegerModeActive
        status.dspCpuLoadPercent = isDspRunning ? dspTelemetry.processingLoadPercent : 0.0
        status.dspRingBufferFillPercent = isDspRunning ? dspTelemetry.ringBufferFillPercent : 0.0

        if isDspRunning {
            switch dspTelemetry.activeMode {
            case .sdmDoP:
                let srcRateInt = max(44_100, Int((activeSourceRate ?? 44_100.0).rounded()))
                let srcBitsInt = activeSourceDepth ?? (srcRateInt >= 48_000 ? 24 : 16)
                let srcBitratePerCh = srcRateInt * srcBitsInt
                let baseGrid = ((srcRateInt % 48_000 == 0) && dspConfig.clockPolicy != .strictSACD44k1) ? 48_000 : 44_100
                let effectiveDsdClockHz = (dspTelemetry.outputSampleRateHz >= 2_822_400)
                    ? dspTelemetry.outputSampleRateHz
                    : (dspConfig.dsdRate.rawValue * baseGrid)
                let effectiveDsdMult = (dspTelemetry.outputSampleRateHz >= 2_822_400)
                    ? max(64, dspTelemetry.outputSampleRateHz / ((dspTelemetry.outputSampleRateHz % 48_000 == 0) ? 48_000 : 44_100))
                    : dspConfig.dsdRate.rawValue
                let mhz = Double(effectiveDsdClockHz) / 1_000_000.0
                status.dspBadge = String(format: "DSD%d DoP · %@ · %.2f МГц", effectiveDsdMult, profileDisplayName, mhz)
                let dsdFallbackToPcm = dspTelemetry.outputSampleRateHz > 0 && dspTelemetry.outputSampleRateHz < 2_822_400
                let isInsufficientDsd = isLosslessQuality && (
                    dsdFallbackToPcm
                    || effectiveDsdClockHz < srcBitratePerCh
                    || (Double(effectiveDsdClockHz) / Double(srcRateInt)) < 32.0
                    || (effectiveDsdMult <= 64 && srcRateInt > 48_000)
                )
                if !dspTelemetry.outputDeviceName.isEmpty {
                    status.audioDeviceName = dspTelemetry.outputDeviceName
                }
                status.audioDeviceSampleRate = Double(dspTelemetry.dopCarrierRateHz)
                status.audioDeviceBitDepth = 24
                status.isBitPerfect = isLosslessQuality && !isInsufficientDsd && !isPreDSPModifyingAudio

            case .hqNOSPCM:
                let effectiveNosRate = (dspTelemetry.outputSampleRateHz > 0) ? dspTelemetry.outputSampleRateHz : dspConfig.maxNOSPCMRateHz
                let khz = Double(effectiveNosRate) / 1_000.0
                let shaperLabel = (dspConfig.nosDitherMode == .lns15) ? "LNS15" : "TPDF"
                status.dspBadge = String(format: "HQ NOS PCM · %@ · %.1f кГц", shaperLabel, khz)
                if !dspTelemetry.outputDeviceName.isEmpty {
                    status.audioDeviceName = dspTelemetry.outputDeviceName
                }
                status.audioDeviceSampleRate = Double(effectiveNosRate)
                status.audioDeviceBitDepth = 24
                status.isBitPerfect = isLosslessQuality && !isPreDSPModifyingAudio

            case .bitPerfectPassthrough:
                status.dspBadge = nil
            }
        } else {
            status.dspBadge = nil
        }

        let saInfo = SpectralIntegrityAnalyzer.shared.getCurrentAnalysis()
        status.spectralAnalysis = saInfo
        MasteringRestorationService.shared.updateTrackDynamicsHint(
            ttDrScore: saInfo.ttDrScore,
            truePeakDbtp: saInfo.truePeakDbtp
        )
        WLEDDDPController.shared.syncCurrentTrackPaletteIfNeeded(track: status.track)
        return (isLosslessQuality, activeSourceRate, activeSourceDepth, baseDeviceRate)
    }

    public func getPlayerStatus() -> PlayerStatus {
        var status = computePlayerStatus()

        var hasConfirmedStreamFormat = true
        let (isStagingBufNow, activeStageNow) = PlaybackStateStore.shared.withLock { () -> (Bool, String?) in
            guard !PlaybackStateStore.shared.isUserPaused else { return (false, nil) }
            return (
                PlaybackStateStore.shared.isActivelyStagingInBuffer,
                PlaybackStateStore.shared.activeLoadingStage
            )
        }
        if status.playerState != "stopped" {
            let tArtist = status.track?.artist ?? ""
            let tName = status.track?.name ?? ""
            let cachedFmt = BitPerfectLogMonitor.shared.getCachedFormat(artist: tArtist, title: tName)
            let detectedRate = BitPerfectLogMonitor.shared.currentDetectedSampleRate
            let detectedDepth = BitPerfectLogMonitor.shared.currentDetectedBitDepth
            let isStreamLossless = (cachedFmt != nil) || (BitPerfectLogMonitor.shared.currentIsLossless && detectedRate != nil)

            if status.track?.isLocal != true {
                let normTrackKey = "\(tArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()):\(tName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                var bufferingNow = false
                var stalledNow = false
                statusLock.lock()
                if normTrackKey != streamTrackKey {
                    streamTrackKey = normTrackKey
                    streamTrackHasAdvanced = (status.position > 0.08)
                    streamTrackZeroPosSince = (status.playerState == "playing" && !streamTrackHasAdvanced) ? Date() : nil
                } else if status.position > 0.08 {
                    streamTrackHasAdvanced = true
                    streamTrackZeroPosSince = nil
                } else if status.playerState == "playing" && !streamTrackHasAdvanced {
                    if streamTrackZeroPosSince == nil {
                        streamTrackZeroPosSince = Date()
                    }
                } else if status.playerState != "playing" {
                    streamTrackZeroPosSince = nil
                }
                let zeroSince = streamTrackZeroPosSince
                let hasAdvanced = streamTrackHasAdvanced
                statusLock.unlock()

                if isStagingBufNow && status.playerState == "playing" && status.position <= 0.08 {
                    bufferingNow = true
                    stalledNow = false
                } else if status.playerState == "playing" && !hasAdvanced && status.position <= 0.08 && !PlaybackRouter.shared.isTestingEnvironment {
                    let isCoreAudioOutputRunning = AudioProcessTapService.isMusicAppRunningAudioOutput()
                    if isCoreAudioOutputRunning {
                        statusLock.lock()
                        streamTrackHasAdvanced = true
                        streamTrackZeroPosSince = nil
                        statusLock.unlock()
                    } else {
                        bufferingNow = true
                        let zeroElapsed = zeroSince.map { Date().timeIntervalSince($0) } ?? 0.0
                        stalledNow = (zeroElapsed >= 5.0)
                    }
                }
                status.isBuffering = bufferingNow
                status.isStreamStalled = stalledNow
                if isStagingBufNow && bufferingNow {
                    status.isStagingBuffer = true
                    status.loadingStage = "buffer"
                } else if bufferingNow {
                    status.isStagingBuffer = false
                    status.loadingStage = activeStageNow ?? "cloud"
                } else {
                    status.isStagingBuffer = false
                    status.loadingStage = nil
                }

                if isStagingBufNow && bufferingNow {
                    status.audioQuality = MusicKitManager.shared.isSystemLocaleRussian
                        ? "Загрузка через буфер AMR…"
                        : "Loading via AMR Buffer…"
                } else if isStreamLossless, let r = cachedFmt?.sampleRate ?? detectedRate {
                    let depth = cachedFmt?.bitDepth ?? detectedDepth ?? (r >= 48000.0 ? 24 : 16)
                    status.track?.sampleRate = Int(r)
                    status.track?.bitDepth = depth
                    if BitPerfectLogMonitor.shared.isEnabled {
                        let khz = r / 1000.0
                        let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
                        status.audioQuality = (r > 48000.0)
                            ? "Hi-Res Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
                            : "Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
                    }
                } else {
                    hasConfirmedStreamFormat = (detectedRate != nil)
                    status.track?.sampleRate = 44100
                    status.track?.bitDepth = 16
                    if hasConfirmedStreamFormat || PlaybackRouter.shared.isTestingEnvironment {
                        status.audioQuality = "AAC (256 kbps)"
                    } else if stalledNow {
                        status.audioQuality = MusicKitManager.shared.isSystemLocaleRussian
                            ? "Ожидание CDN Apple Music…"
                            : "Waiting for Apple Music CDN…"
                    } else if bufferingNow {
                        status.audioQuality = MusicKitManager.shared.isSystemLocaleRussian
                            ? "Буферизация потока…"
                            : "Buffering Stream…"
                    } else if status.playerState == "playing" {
                        status.audioQuality = MusicKitManager.shared.isSystemLocaleRussian
                            ? "Определение формата…"
                            : "Detecting Format…"
                    } else {
                        status.audioQuality = "AAC (256 kbps)"
                    }
                }
            } else {
                status.isBuffering = false
                status.isStreamStalled = false
                status.isStagingBuffer = false
                status.loadingStage = nil
                let isLocalLossless = !status.audioQuality.contains("AAC") && !status.audioQuality.contains("MP3")
                if !isLocalLossless {
                    status.track?.bitDepth = 16
                } else if BitPerfectLogMonitor.shared.isEnabled, let r = status.track?.sampleRate.map({ Double($0) }) ?? detectedRate {
                    let depth = status.track?.bitDepth ?? detectedDepth ?? (r >= 48000.0 ? 24 : 16)
                    let khz = r / 1000.0
                    let khzStr = (khz.truncatingRemainder(dividingBy: 1) == 0) ? String(format: "%.0f", khz) : String(format: "%.1f", khz)
                    status.audioQuality = (r > 48000.0)
                        ? "Hi-Res Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
                        : "Lossless (ALAC \(depth)-bit/\(khzStr)kHz)"
                }
            }
        } else {
            status.isBuffering = false
            status.isStreamStalled = false
            status.isStagingBuffer = false
            status.loadingStage = nil
        }

        let overlayCtx = applyLiveAudioPipelineOverlay(
            to: &status,
            updateTapFormatIfNeeded: status.playerState != "stopped"
        )
        let isLosslessQuality = overlayCtx.isLosslessQuality
        let activeSourceRate = overlayCtx.activeSourceRate
        let activeSourceDepth = overlayCtx.activeSourceDepth
        let devRate = overlayCtx.baseDeviceRate
        let ampCtrl = ExternalAmpTCPController.shared
        let ampActive = ampCtrl.isActive

        let tKey = "\(status.track?.artist ?? ""):\(status.track?.name ?? "")"
        let isStagedTemp = status.track?.numericId.map { nid in
            PlaybackStateStore.shared.withLock { PlaybackStateStore.shared.stagedTemporaryTrackDbIds.contains(nid) }
        } ?? false
        let isLocalTrack = (status.track?.isLocal == true) && !isStagedTemp
        status.track?.isLocal = isLocalTrack
        let uniqueTrackId: String
        if isLocalTrack {
            if let pid = status.track?.persistentId, !pid.isEmpty {
                uniqueTrackId = pid
            } else if let nid = status.track?.numericId, nid > 0 {
                uniqueTrackId = "\(nid)"
            } else {
                uniqueTrackId = (status.track?.id != "0") ? (status.track?.id ?? "") : ""
            }
        } else {
            if let cid = status.track?.catalogId, AppleSoundCheckService.isValidCatalogId(cid) {
                uniqueTrackId = cid
            } else if let cachedCid = MusicKitManager.shared.getCachedTrackCatalogId(
                name: status.track?.name ?? "",
                artist: status.track?.artist ?? "",
                album: status.track?.album ?? ""
            ), AppleSoundCheckService.isValidCatalogId(cachedCid) {
                status.track?.catalogId = cachedCid
                uniqueTrackId = cachedCid
            } else if let pid = status.track?.persistentId, !pid.isEmpty {
                uniqueTrackId = pid
            } else if let nid = status.track?.numericId, nid > 0 {
                uniqueTrackId = "\(nid)"
            } else {
                uniqueTrackId = ""
            }
        }
        let effectiveRate = hasConfirmedStreamFormat
            ? Int(activeSourceRate ?? devRate)
            : Int(devRate.rounded())
        let effectiveDepth = hasConfirmedStreamFormat
            ? (activeSourceDepth ?? (effectiveRate >= 48000 ? 24 : 16))
            : (effectiveRate >= 48000 ? 24 : 16)
        if !PlaybackRouter.shared.isTestingEnvironment {
            SpectralIntegrityAnalyzer.shared.syncTrackContext(
                trackKey: tKey,
                trackId: uniqueTrackId,
                isLocal: isLocalTrack,
                sampleRate: effectiveRate,
                claimedBitDepth: effectiveDepth,
                isLossless: isLosslessQuality,
                isPlaying: status.playerState == "playing"
            )
        }
        status.spectralAnalysis = SpectralIntegrityAnalyzer.shared.getCurrentAnalysis()

        if ampActive, ampCtrl.isSoundCheckEnabled, status.playerState != "stopped", let tr = status.track, !tr.name.isEmpty {
            let validTrackCid = AppleSoundCheckService.isValidCatalogId(tr.catalogId)
                ? tr.catalogId
                : (AppleSoundCheckService.isValidCatalogId(uniqueTrackId) ? uniqueTrackId : nil)
            AppleSoundCheckService.shared.syncCurrentTrack(
                trackKey: tKey,
                trackId: uniqueTrackId,
                catalogId: validTrackCid,
                name: tr.name,
                artist: tr.artist,
                album: tr.album,
                isLocal: isLocalTrack
            )
            status.ampVolume = ampCtrl.currentVolume
            status.volume = ampCtrl.currentVolume
            status.ampSoundCheckGainDb = ampCtrl.currentTrackGainDb
            status.ampSoundCheckOffset = ampCtrl.currentTrackVolumeOffset
            status.ampBaseVolume = ampCtrl.baseListeningVolume

            let (isCustom, customQueue, customIdx) = PlaybackStateStore.shared.withLock {
                (PlaybackStateStore.shared.isCustomQueuePlayback,
                 PlaybackStateStore.shared.activeCustomQueue,
                 PlaybackStateStore.shared.activeCustomQueueIndex)
            }
            if isCustom && !customQueue.isEmpty {
                for offsetIdx in 1...2 {
                    let nextIdx = customIdx + offsetIdx
                    if nextIdx < customQueue.count {
                        let nextTr = customQueue[nextIdx]
                        let nextCid = AppleSoundCheckService.isValidCatalogId(nextTr.catalogId)
                            ? nextTr.catalogId
                            : (AppleSoundCheckService.isValidCatalogId(nextTr.id) ? nextTr.id : nil)
                        AppleSoundCheckService.shared.prefetchTrack(
                            trackId: nextCid ?? nextTr.persistentId ?? nextTr.id,
                            catalogId: nextCid,
                            name: nextTr.name,
                            artist: nextTr.artist,
                            album: nextTr.album
                        )
                    }
                }
            }
        }

        return status
    }
}
