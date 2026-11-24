//
//  Models.swift
//  AppleMusicRemoteMac
//
//  Core player status and spectral analysis models for Apple Music Remote
//

import Foundation

// MARK: - Spectral Integrity & Upsampling Analysis

public struct SpectralAnalysisInfo: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var isCached: Bool
    public var verdict: String
    public var verdictTitle: String
    public var verdictDescription: String
    public var isAuthentic: Bool
    public var sampleRate: Int
    public var claimedBitDepth: Int
    public var effectiveBitDepth: Int
    public var isZeroPadded: Bool
    public var cutoffFrequencyHz: Double
    public var nyquistFrequencyHz: Double
    public var ultrasonicEnergyDb: Double
    public var highBandEnergyDb: Double
    public var dynamicRangeCrestDb: Double
    public var analyzedFramesCount: Int
    public var rtaBands: [Double]
    public var ttDrScore: Int?
    public var ttDrStatus: String
    public var integratedLufs: Double?
    public var shortTermLufs: Double?
    public var momentaryLufs: Double?
    public var loudnessRangeLu: Double?
    public var truePeakDbtp: Double?
    public var ispClipCount: Int
    public var phaseCorrelation: Double
    public var stereoWidthPercent: Double
    public var channelBalanceDb: Double

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case isCached = "is_cached"
        case verdict
        case verdictTitle = "verdict_title"
        case verdictDescription = "verdict_description"
        case isAuthentic = "is_authentic"
        case sampleRate = "sample_rate"
        case claimedBitDepth = "claimed_bit_depth"
        case effectiveBitDepth = "effective_bit_depth"
        case isZeroPadded = "is_zero_padded"
        case cutoffFrequencyHz = "cutoff_frequency_hz"
        case nyquistFrequencyHz = "nyquist_frequency_hz"
        case ultrasonicEnergyDb = "ultrasonic_energy_db"
        case highBandEnergyDb = "high_band_energy_db"
        case dynamicRangeCrestDb = "dynamic_range_crest_db"
        case analyzedFramesCount = "analyzed_frames_count"
        case rtaBands = "rta_bands"
        case ttDrScore = "tt_dr_score"
        case ttDrStatus = "tt_dr_status"
        case integratedLufs = "integrated_lufs"
        case shortTermLufs = "short_term_lufs"
        case momentaryLufs = "momentary_lufs"
        case loudnessRangeLu = "loudness_range_lu"
        case truePeakDbtp = "true_peak_dbtp"
        case ispClipCount = "isp_clip_count"
        case phaseCorrelation = "phase_correlation"
        case stereoWidthPercent = "stereo_width_percent"
        case channelBalanceDb = "channel_balance_db"
    }

    public init(
        isEnabled: Bool = true,
        isCached: Bool = false,
        verdict: String = "analyzing",
        verdictTitle: String = "Спектральный анализ...",
        verdictDescription: String = "Накопление PCM-буферов из CoreAudio Process Tap для расчёта БПФ-спектра.",
        isAuthentic: Bool = true,
        sampleRate: Int = 44100,
        claimedBitDepth: Int = 16,
        effectiveBitDepth: Int = 16,
        isZeroPadded: Bool = false,
        cutoffFrequencyHz: Double = 22050,
        nyquistFrequencyHz: Double = 22050,
        ultrasonicEnergyDb: Double = -96.0,
        highBandEnergyDb: Double = -45.0,
        dynamicRangeCrestDb: Double = 12.0,
        analyzedFramesCount: Int = 0,
        rtaBands: [Double] = Array(repeating: 0.0, count: 32),
        ttDrScore: Int? = nil,
        ttDrStatus: String = "analyzing",
        integratedLufs: Double? = nil,
        shortTermLufs: Double? = nil,
        momentaryLufs: Double? = nil,
        loudnessRangeLu: Double? = nil,
        truePeakDbtp: Double? = nil,
        ispClipCount: Int = 0,
        phaseCorrelation: Double = 1.0,
        stereoWidthPercent: Double = 0.0,
        channelBalanceDb: Double = 0.0
    ) {
        self.isEnabled = isEnabled
        self.isCached = isCached
        self.verdict = verdict
        self.verdictTitle = verdictTitle
        self.verdictDescription = verdictDescription
        self.isAuthentic = isAuthentic
        self.sampleRate = sampleRate
        self.claimedBitDepth = claimedBitDepth
        self.effectiveBitDepth = effectiveBitDepth
        self.isZeroPadded = isZeroPadded
        self.cutoffFrequencyHz = cutoffFrequencyHz
        self.nyquistFrequencyHz = nyquistFrequencyHz
        self.ultrasonicEnergyDb = ultrasonicEnergyDb
        self.highBandEnergyDb = highBandEnergyDb
        self.dynamicRangeCrestDb = dynamicRangeCrestDb
        self.analyzedFramesCount = analyzedFramesCount
        self.rtaBands = rtaBands
        self.ttDrScore = ttDrScore
        self.ttDrStatus = ttDrStatus
        self.integratedLufs = integratedLufs
        self.shortTermLufs = shortTermLufs
        self.momentaryLufs = momentaryLufs
        self.loudnessRangeLu = loudnessRangeLu
        self.truePeakDbtp = truePeakDbtp
        self.ispClipCount = ispClipCount
        self.phaseCorrelation = phaseCorrelation
        self.stereoWidthPercent = stereoWidthPercent
        self.channelBalanceDb = channelBalanceDb
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.isCached = try container.decodeIfPresent(Bool.self, forKey: .isCached) ?? false
        self.verdict = try container.decodeIfPresent(String.self, forKey: .verdict) ?? "analyzing"
        self.verdictTitle = try container.decodeIfPresent(String.self, forKey: .verdictTitle) ?? "Спектральный анализ..."
        self.verdictDescription = try container.decodeIfPresent(String.self, forKey: .verdictDescription) ?? ""
        self.isAuthentic = try container.decodeIfPresent(Bool.self, forKey: .isAuthentic) ?? true
        self.sampleRate = try container.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 44100
        self.claimedBitDepth = try container.decodeIfPresent(Int.self, forKey: .claimedBitDepth) ?? 16
        self.effectiveBitDepth = try container.decodeIfPresent(Int.self, forKey: .effectiveBitDepth) ?? 16
        self.isZeroPadded = try container.decodeIfPresent(Bool.self, forKey: .isZeroPadded) ?? false
        self.cutoffFrequencyHz = try container.decodeIfPresent(Double.self, forKey: .cutoffFrequencyHz) ?? 22050
        self.nyquistFrequencyHz = try container.decodeIfPresent(Double.self, forKey: .nyquistFrequencyHz) ?? 22050
        self.ultrasonicEnergyDb = try container.decodeIfPresent(Double.self, forKey: .ultrasonicEnergyDb) ?? -96.0
        self.highBandEnergyDb = try container.decodeIfPresent(Double.self, forKey: .highBandEnergyDb) ?? -45.0
        self.dynamicRangeCrestDb = try container.decodeIfPresent(Double.self, forKey: .dynamicRangeCrestDb) ?? 12.0
        self.analyzedFramesCount = try container.decodeIfPresent(Int.self, forKey: .analyzedFramesCount) ?? 0
        self.rtaBands = try container.decodeIfPresent([Double].self, forKey: .rtaBands) ?? Array(repeating: 0.0, count: 32)
        self.ttDrScore = try container.decodeIfPresent(Int.self, forKey: .ttDrScore)
        self.ttDrStatus = try container.decodeIfPresent(String.self, forKey: .ttDrStatus) ?? "analyzing"
        self.integratedLufs = try container.decodeIfPresent(Double.self, forKey: .integratedLufs)
        self.shortTermLufs = try container.decodeIfPresent(Double.self, forKey: .shortTermLufs)
        self.momentaryLufs = try container.decodeIfPresent(Double.self, forKey: .momentaryLufs)
        self.loudnessRangeLu = try container.decodeIfPresent(Double.self, forKey: .loudnessRangeLu)
        self.truePeakDbtp = try container.decodeIfPresent(Double.self, forKey: .truePeakDbtp)
        self.ispClipCount = try container.decodeIfPresent(Int.self, forKey: .ispClipCount) ?? 0
        self.phaseCorrelation = try container.decodeIfPresent(Double.self, forKey: .phaseCorrelation) ?? 1.0
        self.stereoWidthPercent = try container.decodeIfPresent(Double.self, forKey: .stereoWidthPercent) ?? 0.0
        self.channelBalanceDb = try container.decodeIfPresent(Double.self, forKey: .channelBalanceDb) ?? 0.0
    }
}

// MARK: - Player Status

public struct PlayerStatus: Codable, Sendable {
    public var playerState: String
    public var position: Double
    public var duration: Double
    public var volume: Int
    public var shuffle: Bool
    public var repeatMode: String
    public var playlist: String
    public var isRadio: Bool
    public var audioQuality: String
    public var isMusicAppRunning: Bool
    public var isDucked: Bool
    public var isVolumeLockedTo100: Bool
    public var track: TrackInfo?
    public var audioDeviceName: String?
    public var audioDeviceSampleRate: Double?
    public var audioDeviceBitDepth: Int?
    public var isBitPerfect: Bool?
    public var isClockSyncedDsp: Bool?
    public var isDacMutingGuardEnabled: Bool?
    public var dacMutingGuardMs: Int?
    public var spectralAnalysis: SpectralAnalysisInfo?
    public var ampVolumeControlEnabled: Bool?
    public var ampBrandName: String?
    public var ampVolume: Int?
    public var ampMaxVolume: Int?
    public var ampMuted: Bool?
    public var ampConnected: Bool?
    public var ampSoundCheckEnabled: Bool?
    public var ampLowVolSmartNormEnabled: Bool?
    public var ampSoundCheckGainDb: Double?
    public var ampSoundCheckOffset: Int?
    public var ampBaseVolume: Int?
    public var dspMode: String?
    public var dspBadge: String?
    public var dspProfile: String?
    public var dspOutputSampleRate: Int?
    public var dspDoPCarrierRate: Int?
    public var dspIsHogMode: Bool?
    public var dspIsIntegerMode: Bool?
    public var dspCpuLoadPercent: Double?
    public var dspRingBufferFillPercent: Double?
    public var isDlnaActive: Bool?
    public var roomCorrectionActive: Bool?
    public var roomProfileName: String?
    public var lateNightDrcMode: String?
    public var lateNightDrcEnabled: Bool?
    public var lateNightDrcProfile: String?
    public var lateNightDrcGainDb: Double?
    public var masteringDeclipMode: String?
    public var masteringDeclipRestoredDb: Double?
    public var masteringDeesserMode: String?
    public var masteringDeesserGainDb: Double?
    public var isBuffering: Bool?
    public var isStreamStalled: Bool?
    public var isStagingBuffer: Bool?
    public var loadingStage: String?

    enum CodingKeys: String, CodingKey {
        case playerState = "player_state"
        case position
        case duration
        case volume
        case shuffle
        case repeatMode = "repeat"
        case playlist
        case isRadio = "is_radio"
        case audioQuality = "audio_quality"
        case isMusicAppRunning = "is_music_app_running"
        case isDucked = "is_ducked"
        case isVolumeLockedTo100 = "lock_volume_100"
        case track
        case audioDeviceName = "audio_device_name"
        case audioDeviceSampleRate = "audio_device_sample_rate"
        case audioDeviceBitDepth = "audio_device_bit_depth"
        case isBitPerfect = "is_bit_perfect"
        case isClockSyncedDsp = "is_clock_synced_dsp"
        case isDacMutingGuardEnabled = "dac_muting_guard_enabled"
        case dacMutingGuardMs = "dac_muting_guard_ms"
        case spectralAnalysis = "spectral_analysis"
        case ampVolumeControlEnabled = "amp_volume_control"
        case ampBrandName = "amp_brand_name"
        case ampVolume = "amp_volume"
        case ampMaxVolume = "amp_max_volume"
        case ampMuted = "amp_muted"
        case ampConnected = "amp_connected"
        case ampSoundCheckEnabled = "amp_soundcheck_enabled"
        case ampLowVolSmartNormEnabled = "amp_low_vol_smart_norm_enabled"
        case ampSoundCheckGainDb = "amp_soundcheck_gain_db"
        case ampSoundCheckOffset = "amp_soundcheck_offset"
        case ampBaseVolume = "amp_base_volume"
        case dspMode = "dsp_mode"
        case dspBadge = "dsp_badge"
        case dspProfile = "dsp_profile"
        case dspOutputSampleRate = "dsp_output_sample_rate"
        case dspDoPCarrierRate = "dsp_dop_carrier_rate"
        case dspIsHogMode = "dsp_is_hog_mode"
        case dspIsIntegerMode = "dsp_is_integer_mode"
        case dspCpuLoadPercent = "dsp_cpu_load_percent"
        case dspRingBufferFillPercent = "dsp_ring_buffer_fill_percent"
        case isDlnaActive = "is_dlna_active"
        case roomCorrectionActive = "room_correction_active"
        case roomProfileName = "room_profile_name"
        case lateNightDrcMode = "late_night_drc_mode"
        case lateNightDrcEnabled = "late_night_drc_enabled"
        case lateNightDrcProfile = "late_night_drc_profile"
        case lateNightDrcGainDb = "late_night_drc_gain_db"
        case masteringDeclipMode = "mastering_declip_mode"
        case masteringDeclipRestoredDb = "mastering_declip_restored_db"
        case masteringDeesserMode = "mastering_deesser_mode"
        case masteringDeesserGainDb = "mastering_deesser_gain_db"
        case isBuffering = "is_buffering"
        case isStreamStalled = "is_stream_stalled"
        case isStagingBuffer = "is_staging_buffer"
        case loadingStage = "loading_stage"
    }

    public init(
        playerState: String = "stopped",
        position: Double = 0,
        duration: Double = 0,
        volume: Int = 50,
        shuffle: Bool = false,
        repeatMode: String = "off",
        playlist: String = "Музыка",
        isRadio: Bool = false,
        audioQuality: String = "Lossless (ALAC 24-bit/48kHz)",
        isMusicAppRunning: Bool = true,
        isDucked: Bool = false,
        isVolumeLockedTo100: Bool = true,
        track: TrackInfo? = nil,
        audioDeviceName: String? = nil,
        audioDeviceSampleRate: Double? = nil,
        audioDeviceBitDepth: Int? = nil,
        isBitPerfect: Bool? = nil,
        isClockSyncedDsp: Bool? = nil,
        isDacMutingGuardEnabled: Bool? = nil,
        dacMutingGuardMs: Int? = nil,
        spectralAnalysis: SpectralAnalysisInfo? = nil,
        ampVolumeControlEnabled: Bool? = nil,
        ampBrandName: String? = nil,
        ampVolume: Int? = nil,
        ampMaxVolume: Int? = nil,
        ampMuted: Bool? = nil,
        ampConnected: Bool? = nil,
        ampSoundCheckEnabled: Bool? = nil,
        ampLowVolSmartNormEnabled: Bool? = nil,
        ampSoundCheckGainDb: Double? = nil,
        ampSoundCheckOffset: Int? = nil,
        ampBaseVolume: Int? = nil,
        dspMode: String? = nil,
        dspBadge: String? = nil,
        dspProfile: String? = nil,
        dspOutputSampleRate: Int? = nil,
        dspDoPCarrierRate: Int? = nil,
        dspIsHogMode: Bool? = nil,
        dspIsIntegerMode: Bool? = nil,
        dspCpuLoadPercent: Double? = nil,
        dspRingBufferFillPercent: Double? = nil,
        isDlnaActive: Bool? = nil,
        roomCorrectionActive: Bool? = nil,
        roomProfileName: String? = nil,
        lateNightDrcMode: String? = nil,
        lateNightDrcEnabled: Bool? = nil,
        lateNightDrcProfile: String? = nil,
        lateNightDrcGainDb: Double? = nil,
        masteringDeclipMode: String? = nil,
        masteringDeclipRestoredDb: Double? = nil,
        masteringDeesserMode: String? = nil,
        masteringDeesserGainDb: Double? = nil,
        isBuffering: Bool? = nil,
        isStreamStalled: Bool? = nil,
        isStagingBuffer: Bool? = nil,
        loadingStage: String? = nil
    ) {
        self.playerState = playerState
        self.position = position
        self.duration = duration
        self.volume = volume
        self.shuffle = shuffle
        self.repeatMode = repeatMode
        self.playlist = playlist
        self.isRadio = isRadio
        self.audioQuality = audioQuality
        self.isMusicAppRunning = isMusicAppRunning
        self.isDucked = isDucked
        self.isVolumeLockedTo100 = isVolumeLockedTo100
        self.track = track
        self.audioDeviceName = audioDeviceName
        self.audioDeviceSampleRate = audioDeviceSampleRate
        self.audioDeviceBitDepth = audioDeviceBitDepth
        self.isBitPerfect = isBitPerfect
        self.isClockSyncedDsp = isClockSyncedDsp
        self.isDacMutingGuardEnabled = isDacMutingGuardEnabled
        self.dacMutingGuardMs = dacMutingGuardMs
        self.spectralAnalysis = spectralAnalysis
        self.ampVolumeControlEnabled = ampVolumeControlEnabled
        self.ampBrandName = ampBrandName
        self.ampVolume = ampVolume
        self.ampMaxVolume = ampMaxVolume
        self.ampMuted = ampMuted
        self.ampConnected = ampConnected
        self.ampSoundCheckEnabled = ampSoundCheckEnabled
        self.ampLowVolSmartNormEnabled = ampLowVolSmartNormEnabled
        self.ampSoundCheckGainDb = ampSoundCheckGainDb
        self.ampSoundCheckOffset = ampSoundCheckOffset
        self.ampBaseVolume = ampBaseVolume
        self.dspMode = dspMode
        self.dspBadge = dspBadge
        self.dspProfile = dspProfile
        self.dspOutputSampleRate = dspOutputSampleRate
        self.dspDoPCarrierRate = dspDoPCarrierRate
        self.dspIsHogMode = dspIsHogMode
        self.dspIsIntegerMode = dspIsIntegerMode
        self.dspCpuLoadPercent = dspCpuLoadPercent
        self.dspRingBufferFillPercent = dspRingBufferFillPercent
        self.isDlnaActive = isDlnaActive
        self.roomCorrectionActive = roomCorrectionActive
        self.roomProfileName = roomProfileName
        self.lateNightDrcMode = lateNightDrcMode
        self.lateNightDrcEnabled = lateNightDrcEnabled
        self.lateNightDrcProfile = lateNightDrcProfile
        self.lateNightDrcGainDb = lateNightDrcGainDb
        self.masteringDeclipMode = masteringDeclipMode
        self.masteringDeclipRestoredDb = masteringDeclipRestoredDb
        self.masteringDeesserMode = masteringDeesserMode
        self.masteringDeesserGainDb = masteringDeesserGainDb
        self.isBuffering = isBuffering
        self.isStreamStalled = isStreamStalled
        self.isStagingBuffer = isStagingBuffer
        self.loadingStage = loadingStage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.playerState = try container.decodeIfPresent(String.self, forKey: .playerState) ?? "stopped"
        self.position = try container.decodeIfPresent(Double.self, forKey: .position) ?? 0
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        self.volume = try container.decodeIfPresent(Int.self, forKey: .volume) ?? 50
        self.shuffle = try container.decodeIfPresent(Bool.self, forKey: .shuffle) ?? false
        self.repeatMode = try container.decodeIfPresent(String.self, forKey: .repeatMode) ?? "off"
        self.playlist = try container.decodeIfPresent(String.self, forKey: .playlist) ?? "Музыка"
        self.isRadio = try container.decodeIfPresent(Bool.self, forKey: .isRadio) ?? false
        self.audioQuality = try container.decodeIfPresent(String.self, forKey: .audioQuality) ?? "Lossless"
        self.isMusicAppRunning = try container.decodeIfPresent(Bool.self, forKey: .isMusicAppRunning) ?? true
        self.isDucked = try container.decodeIfPresent(Bool.self, forKey: .isDucked) ?? false
        self.isVolumeLockedTo100 = try container.decodeIfPresent(Bool.self, forKey: .isVolumeLockedTo100) ?? true
        self.track = try container.decodeIfPresent(TrackInfo.self, forKey: .track)
        self.audioDeviceName = try container.decodeIfPresent(String.self, forKey: .audioDeviceName)
        self.audioDeviceSampleRate = try container.decodeIfPresent(Double.self, forKey: .audioDeviceSampleRate)
        self.audioDeviceBitDepth = try container.decodeIfPresent(Int.self, forKey: .audioDeviceBitDepth)
        self.isBitPerfect = try container.decodeIfPresent(Bool.self, forKey: .isBitPerfect)
        self.isClockSyncedDsp = try container.decodeIfPresent(Bool.self, forKey: .isClockSyncedDsp)
        self.isDacMutingGuardEnabled = try container.decodeIfPresent(Bool.self, forKey: .isDacMutingGuardEnabled)
        self.dacMutingGuardMs = try container.decodeIfPresent(Int.self, forKey: .dacMutingGuardMs)
        self.spectralAnalysis = try container.decodeIfPresent(SpectralAnalysisInfo.self, forKey: .spectralAnalysis)
        self.ampVolumeControlEnabled = try container.decodeIfPresent(Bool.self, forKey: .ampVolumeControlEnabled)
        self.ampBrandName = try container.decodeIfPresent(String.self, forKey: .ampBrandName)
        self.ampVolume = try container.decodeIfPresent(Int.self, forKey: .ampVolume)
        self.ampMaxVolume = try container.decodeIfPresent(Int.self, forKey: .ampMaxVolume)
        self.ampMuted = try container.decodeIfPresent(Bool.self, forKey: .ampMuted)
        self.ampConnected = try container.decodeIfPresent(Bool.self, forKey: .ampConnected)
        self.ampSoundCheckEnabled = try container.decodeIfPresent(Bool.self, forKey: .ampSoundCheckEnabled)
        self.ampLowVolSmartNormEnabled = try container.decodeIfPresent(Bool.self, forKey: .ampLowVolSmartNormEnabled)
        self.ampSoundCheckGainDb = try container.decodeIfPresent(Double.self, forKey: .ampSoundCheckGainDb)
        self.ampSoundCheckOffset = try container.decodeIfPresent(Int.self, forKey: .ampSoundCheckOffset)
        self.ampBaseVolume = try container.decodeIfPresent(Int.self, forKey: .ampBaseVolume)
        self.dspMode = try container.decodeIfPresent(String.self, forKey: .dspMode)
        self.dspBadge = try container.decodeIfPresent(String.self, forKey: .dspBadge)
        self.dspProfile = try container.decodeIfPresent(String.self, forKey: .dspProfile)
        self.dspOutputSampleRate = try container.decodeIfPresent(Int.self, forKey: .dspOutputSampleRate)
        self.dspDoPCarrierRate = try container.decodeIfPresent(Int.self, forKey: .dspDoPCarrierRate)
        self.dspIsHogMode = try container.decodeIfPresent(Bool.self, forKey: .dspIsHogMode)
        self.dspIsIntegerMode = try container.decodeIfPresent(Bool.self, forKey: .dspIsIntegerMode)
        self.dspCpuLoadPercent = try container.decodeIfPresent(Double.self, forKey: .dspCpuLoadPercent)
        self.dspRingBufferFillPercent = try container.decodeIfPresent(Double.self, forKey: .dspRingBufferFillPercent)
        self.isDlnaActive = try container.decodeIfPresent(Bool.self, forKey: .isDlnaActive)
        self.roomCorrectionActive = try container.decodeIfPresent(Bool.self, forKey: .roomCorrectionActive)
        self.roomProfileName = try container.decodeIfPresent(String.self, forKey: .roomProfileName)
        self.lateNightDrcMode = try container.decodeIfPresent(String.self, forKey: .lateNightDrcMode)
        self.lateNightDrcEnabled = try container.decodeIfPresent(Bool.self, forKey: .lateNightDrcEnabled)
        self.lateNightDrcProfile = try container.decodeIfPresent(String.self, forKey: .lateNightDrcProfile)
        self.lateNightDrcGainDb = try container.decodeIfPresent(Double.self, forKey: .lateNightDrcGainDb)
        self.masteringDeclipMode = try container.decodeIfPresent(String.self, forKey: .masteringDeclipMode)
        self.masteringDeclipRestoredDb = try container.decodeIfPresent(Double.self, forKey: .masteringDeclipRestoredDb)
        self.masteringDeesserMode = try container.decodeIfPresent(String.self, forKey: .masteringDeesserMode)
        self.masteringDeesserGainDb = try container.decodeIfPresent(Double.self, forKey: .masteringDeesserGainDb)
        self.isBuffering = try container.decodeIfPresent(Bool.self, forKey: .isBuffering)
        self.isStreamStalled = try container.decodeIfPresent(Bool.self, forKey: .isStreamStalled)
        self.isStagingBuffer = try container.decodeIfPresent(Bool.self, forKey: .isStagingBuffer)
        self.loadingStage = try container.decodeIfPresent(String.self, forKey: .loadingStage)
    }

    public var isPlaying: Bool {
        return playerState == "playing"
    }
}
