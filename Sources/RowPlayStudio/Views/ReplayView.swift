import Foundation
import RowPlayCore
import RowPlayPlatform
import SwiftUI
import UniformTypeIdentifiers

struct ReplayView: View {
    static let qualityAccessibilityLabel = "3D replay quality"
    static let qualityPickerHelp = "Choose the maximum 3D replay quality"
    static let adaptiveQualityHelp = "Quality was reduced to maintain replay performance"
    private static let candidateDateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(.autoupdatingCurrent)
    private static let finishEpsilon: TimeInterval = 0.05

    let detail: WorkoutDetail
    let ghostCandidates: [WorkoutDetail]
    private let ghostCandidateByID: [Int: WorkoutDetail]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var currentLocale
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.automationModeEnabled) private var automationModeEnabled
    @State private var state: ReplayState
    @State private var lastTickDate: Date?
    @State private var rendererMode: ReplayRendererMode = .threeD
    @State private var cameraPreset: ReplayCameraPreset = .chase
    @State private var effectiveReplayQuality: ReplayRenderQuality?
    @State private var cameraResetGeneration = 0
    @State private var replayDiscontinuityGeneration = 0
    @State private var strokePath = Path()
    @State private var ghostStrokePath = Path()
    @State private var canvasSize: CGSize = .zero
    @State private var cachedMachineColor: Color = .accentColor
    @State private var activeRival: ReplayRival?
    @State private var cachedRaceResult: ReplayRaceResult?
    @State private var showPaceEditor = false
    @State private var paceInputText = ""
    @State private var paceValidationError: String?
    @State private var showFileImporter = false
    @State private var isImportingRival = false
    @State private var rivalImportGeneration = ReplayRivalImportGeneration()
    @State private var rivalImportTask: Task<Void, Never>?
    @State private var rivalErrorMessage: String?
    @State private var showReportExporter = false
    @State private var showCardExporter = false
    @State private var exportReportItem: ReplayRaceReportTransferItem?
    @State private var exportCardItem: ReplayRaceCardTransferItem?
    @State private var shareCardItem: ReplayRaceCardTransferItem?

    private var unit: DistanceUnit { preferences.distanceUnit }
    private var reduceMotion: Bool { preferences.reduceReplayMotion || automationModeEnabled }

    init(
        detail: WorkoutDetail,
        ghostCandidates: [WorkoutDetail] = [],
        initialGhostID: Int? = nil
    ) {
        self.detail = detail
        self.ghostCandidates = ghostCandidates
        let candidateByID = ghostCandidates.reduce(into: [Int: WorkoutDetail]()) { result, candidate in
            result[candidate.id] = candidate
        }
        self.ghostCandidateByID = candidateByID
        _state = State(initialValue: ReplayState(strokes: detail.strokes))
        let initialRival: ReplayRival? = {
            guard let id = initialGhostID,
                  let candidate = candidateByID[id] else {
                return nil
            }
            return ReplayRivalFactory.makeSessionRival(from: candidate)
        }()
        _activeRival = State(initialValue: initialRival)
        if let rival = initialRival {
            _cachedRaceResult = State(initialValue: ReplayRaceResultCalculator.result(
                playerStrokes: detail.strokes,
                rivalStrokes: rival.strokes,
                workout: detail.workout
            ))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            rendererPicker
            rivalControlBand
            if let error = rivalErrorMessage {
                Text(error)
                    .font(AppDesign.Typography.compactLabel)
                    .foregroundStyle(AppDesign.alertRed)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Rival error")
                    .accessibilityValue(error)
            }
            if isImportingRival {
                ProgressView("Importing rival…")
                    .controlSize(.small)
                    .padding(.vertical, 4)
                    .accessibilityLabel("Importing rival")
            }
            replaySurface
            if showsFinishVerdict, let rival = activeRival, let result = cachedRaceResult {
                finishVerdictBanner(rival: rival, result: result)
            }
            Divider()
            telemetryBar
            Divider()
            playbackControls
        }
        .navigationTitle("Replay")
        .onChange(of: state.playing) { _, playing in
            if playing {
                lastTickDate = nil
            }
        }
        .onDisappear {
            cancelRivalImport()
            state.pause()
        }
        .onChange(of: preferences.replayRenderQuality) { _, quality in
            effectiveReplayQuality = quality
        }
        .onChange(of: colorScheme) { _, _ in
            shareCardItem = nil
            prepareShareCardIfFinished()
        }
        .onChange(of: activeRival?.id) { _, _ in
            handleRivalChange()
        }
        .onChange(of: showsFinishVerdict) { _, isFinished in
            guard isFinished else { return }
            prepareShareCardIfFinished()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.rivalImportTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .fileExporter(
            isPresented: $showReportExporter,
            item: exportReportItem,
            contentTypes: [.json],
            defaultFilename: exportReportItem?.suggestedName ?? ReplayRaceSuggestedFilename.report
        ) { result in
            exportReportItem = nil
            if case .failure(let error) = result, !Self.isUserCancellation(error) {
                rivalErrorMessage = "Could not save race report"
            }
        }
        .fileExporter(
            isPresented: $showCardExporter,
            item: exportCardItem,
            contentTypes: [.png],
            defaultFilename: exportCardItem?.suggestedName ?? ReplayRaceSuggestedFilename.card
        ) { result in
            exportCardItem = nil
            if case .failure(let error) = result, !Self.isUserCancellation(error) {
                rivalErrorMessage = "Could not save race card"
            }
        }
        .popover(isPresented: $showPaceEditor, arrowEdge: .bottom) {
            paceEditorPopover
        }
    }

    // MARK: - Renderer Picker

    private var rendererPicker: some View {
        HStack(spacing: AppDesign.Spacing.medium) {
            Spacer()
            Picker("Renderer", selection: Binding(
                get: { rendererMode },
                set: { mode in
                    lastTickDate = nil
                    rendererMode = mode
                }
            )) {
                ForEach(visibleRendererModes) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 140)

            if Self.showsQualityControl(rendererMode: rendererMode) {
                Divider()
                    .frame(height: 20)

                Picker(selection: $cameraPreset) {
                    ForEach(ReplayCameraPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                } label: {
                    Label(cameraPreset.displayName, systemImage: cameraPreset.systemImage)
                }
                .pickerStyle(.menu)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Replay camera")
                .accessibilityValue(cameraPreset.displayName)
                #if os(macOS)
                .help("Replay camera")
                #endif

                qualityPicker

                Button {
                    cameraResetGeneration &+= 1
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset replay camera")
                #if os(macOS)
                .help("Reset replay camera")
                #endif
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    // MARK: - Rival Control Band

    private var rivalControlBand: some View {
        HStack(spacing: AppDesign.Spacing.medium) {
            Menu {
                Button {
                    selectRival(nil)
                } label: {
                    HStack {
                        Text("No Rival")
                        if activeRival == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                if !ghostCandidates.isEmpty {
                    Button {
                        if let best = ghostCandidates.first,
                           let rival = ReplayRivalFactory.makeSessionRival(from: best) {
                            selectRival(rival)
                        }
                    } label: {
                        HStack {
                            Text("Best Match")
                            if isBestMatchSelected {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if !ghostCandidates.isEmpty {
                    Divider()
                    ForEach(ghostCandidates) { candidate in
                        Button {
                            if let rival = ReplayRivalFactory.makeSessionRival(from: candidate) {
                                selectRival(rival)
                            }
                        } label: {
                            HStack {
                                candidateLabel(for: candidate)
                                if activeRival?.sessionWorkoutID == candidate.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Divider()

                Button("Set Constant Pace…") {
                    paceInputText = PaceInput.formatPaceInput(detail.workout.pace)
                    paceValidationError = nil
                    showPaceEditor = true
                }

                Button("Import Rival File…") {
                    showFileImporter = true
                }
                .disabled(isImportingRival)
                #if os(macOS)
                .help(isImportingRival
                    ? "A rival file is already being imported"
                    : "Choose a CSV, TCX, or FIT rival file")
                #endif
            } label: {
                Label("Replay rival", systemImage: "person.2.fill")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Replay rival")
            .accessibilityValue(rivalAccessibilityValue)
            #if os(macOS)
            .help("Choose a past session, constant pace, or imported file rival")
            #endif

            if let active = activeRival {
                rivalGapDisplay(for: active)
            }

            Spacer()

            if activeRival != nil {
                Button {
                    selectRival(nil)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove replay rival")
                #if os(macOS)
                .help("Remove replay rival")
                #endif
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    private var isBestMatchSelected: Bool {
        guard let bestID = ghostCandidates.first?.id else { return false }
        return activeRival?.sessionWorkoutID == bestID
    }

    private var paceEditorPopover: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.medium) {
            Text("Constant pace")
                .font(AppDesign.Typography.compactLabel)
                .foregroundStyle(.secondary)
            TextField("M:SS", text: $paceInputText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .accessibilityLabel("Constant pace input")
                .onSubmit { applyConstantPace() }
            if let paceValidationError {
                Text(paceValidationError)
                    .font(AppDesign.Typography.compactLabel)
                    .foregroundStyle(AppDesign.alertRed)
                    .accessibilityLabel("Pace validation error")
                    .accessibilityValue(paceValidationError)
            }
            HStack {
                Button("Cancel") {
                    showPaceEditor = false
                    paceValidationError = nil
                }
                Button("Set Pace") {
                    applyConstantPace()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 200)
    }

    private func applyConstantPace() {
        guard let pace = PaceInput.parsePaceInput(paceInputText) else {
            paceValidationError = "Enter a valid pace such as 1:52"
            // Do not replace the current rival when invalid.
            return
        }
        guard let rival = ReplayRivalFactory.makeConstantPaceRival(
            pacePer500m: pace,
            player: detail.workout
        ) else {
            paceValidationError = "Could not create a pace boat for this workout"
            return
        }
        paceValidationError = nil
        showPaceEditor = false
        selectRival(rival)
    }

    /// Every direct selection invalidates any detached import that was already
    /// in flight, so an older completion cannot replace the user's newer choice.
    private func selectRival(_ rival: ReplayRival?) {
        cancelRivalImport()
        activeRival = rival
        rivalErrorMessage = nil
    }

    private func cancelRivalImport() {
        _ = rivalImportGeneration.advance()
        rivalImportTask?.cancel()
        rivalImportTask = nil
        isImportingRival = false
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            guard !Self.isUserCancellation(error) else { return }
            // File-panel errors can contain a full local path. Keep the UI
            // actionable without surfacing that path.
            rivalErrorMessage = "Could not open the selected rival file"
        case .success(let urls):
            guard let url = urls.first else { return }
            rivalImportTask?.cancel()
            let importToken = rivalImportGeneration.advance()
            isImportingRival = true
            rivalErrorMessage = nil
            let lastComponent = url.lastPathComponent
            rivalImportTask = Task { @MainActor in
                let worker = Task.detached(priority: .userInitiated) {
                    try ReplayRivalImportLoader.loadSecurityScopedRival(
                        from: url,
                        fileName: lastComponent
                    )
                }
                do {
                    let rival = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    guard rivalImportGeneration.accepts(importToken) else { return }
                    rivalImportTask = nil
                    isImportingRival = false
                    activeRival = rival
                    rivalErrorMessage = nil
                } catch {
                    guard rivalImportGeneration.accepts(importToken) else { return }
                    rivalImportTask = nil
                    isImportingRival = false
                    guard !Self.isUserCancellation(error) else { return }
                    // Preserve current rival on failure.
                    if let parserError = error as? ReplayRivalFileParserError {
                        rivalErrorMessage = parserError.errorDescription
                    } else {
                        rivalErrorMessage = "Could not import rival file"
                    }
                }
            }
        }
    }

    private func handleRivalChange() {
        // Preserve replay time, play/pause, speed, renderer, camera, quality.
        replayDiscontinuityGeneration &+= 1
        shareCardItem = nil
        ghostStrokePath = Path()
        if canvasSize != .zero, let rival = activeRival {
            ghostStrokePath = makeGhostStrokePath(
                ghostStrokes: rival.strokes,
                playerStrokes: detail.strokes,
                size: canvasSize
            )
        }
        // Cache race result once rather than recomputing every frame.
        if let rival = activeRival {
            cachedRaceResult = ReplayRaceResultCalculator.result(
                playerStrokes: detail.strokes,
                rivalStrokes: rival.strokes,
                workout: detail.workout
            )
        } else {
            cachedRaceResult = nil
        }
        prepareShareCardIfFinished()
    }

    private func candidateLabel(for candidate: WorkoutDetail) -> some View {
        let w = candidate.workout
        let dateStr = w.date.formatted(Self.candidateDateStyle.locale(currentLocale))
        let distStr = RowPlayFormatting.distance(w.distance, unit: unit)
        let paceStr = RowPlayFormatting.pace(w.pace)
        return Text("\(dateStr) · \(distStr) · \(paceStr)")
            .accessibilityLabel("\(dateStr), \(distStr), \(paceStr)")
    }

    private var rivalAccessibilityValue: String {
        guard let active = activeRival else {
            return "No rival selected"
        }
        switch active.kind {
        case .session:
            if let id = active.sessionWorkoutID,
               let candidate = ghostCandidateByID[id] {
                let w = candidate.workout
                let dist = RowPlayFormatting.distance(w.distance, unit: unit)
                let pace = RowPlayFormatting.pace(w.pace)
                return "Rival: \(dist) at \(pace) from \(w.date.formatted(Self.candidateDateStyle.locale(currentLocale)))"
            }
            return "Past session rival"
        case .constantPace:
            if let pace = active.targetPace {
                return "Pace boat \(RowPlayFormatting.pace(pace))"
            }
            return "Pace boat"
        case .importedFile:
            if let name = active.localFileName {
                return "Imported rival \(name)"
            }
            return "Imported rival"
        }
    }

    @ViewBuilder
    private func rivalGapDisplay(for rival: ReplayRival) -> some View {
        let frame = state.currentFrame
        let ghostDist = ReplayRaceGap.ghostDistance(elapsed: state.time, strokes: rival.strokes)
        let gapM = ReplayRaceGap.raceGapMeters(
            playerDistance: frame.d,
            ghostDistance: ghostDist
        )
        let gapS = ReplayRaceGap.raceGapSeconds(
            gapMeters: gapM,
            playerPacePer500m: frame.pace
        )
        let gapColor = AppDesign.deltaColor(gapM, higherIsBetter: true)

        HStack(spacing: AppDesign.Spacing.small) {
            Text(rivalShortLabel(rival))
                .font(AppDesign.Typography.compactLabel)
                .foregroundStyle(.secondary)

            Text(gapLabel(meters: gapM))
                .font(AppDesign.Typography.compactLabel.monospacedDigit())
                .foregroundStyle(gapColor)

            Text("·")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(gapSecondsLabel(seconds: gapS))
                .font(AppDesign.Typography.compactLabel.monospacedDigit())
                .foregroundStyle(gapColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Race gap")
        .accessibilityValue("\(gapLabel(meters: gapM)), \(gapSecondsLabel(seconds: gapS))")
    }

    private func rivalShortLabel(_ rival: ReplayRival) -> String {
        switch rival.kind {
        case .session:
            if let id = rival.sessionWorkoutID,
               let candidate = ghostCandidateByID[id] {
                return candidate.workout.date.formatted(Self.candidateDateStyle.locale(currentLocale))
            }
            return "Session"
        case .constantPace:
            return rival.displayLabel
        case .importedFile:
            return rival.localFileName ?? "Imported"
        }
    }

    private func gapLabel(meters: Double) -> String {
        let safeM = meters.isFinite ? meters : 0
        if abs(safeM) < 0.5 { return "Level" }
        let prefix = safeM > 0 ? "Ahead" : "Behind"
        let dist = RowPlayFormatting.distance(abs(safeM), unit: unit)
        return "\(prefix) \(dist)"
    }

    private func gapSecondsLabel(seconds: Double) -> String {
        let safeS = seconds.isFinite ? seconds : 0
        let absS = abs(safeS)
        if absS < 0.05 { return "0.0 s" }
        let sign = safeS > 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.1f", absS)) s"
    }

    private var visibleRendererModes: [ReplayRendererMode] {
        ReplayRendererMode.allCases
    }

    private static var rivalImportTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .xml, .data]
        if let tcx = UTType(filenameExtension: "tcx") {
            types.append(tcx)
        }
        if let fit = UTType(filenameExtension: "fit") {
            types.append(fit)
        }
        if let csv = UTType(filenameExtension: "csv") {
            types.append(csv)
        }
        return types
    }

    // MARK: - Finish Verdict

    private var showsFinishVerdict: Bool {
        guard activeRival != nil, cachedRaceResult != nil else { return false }
        let duration = state.duration
        guard duration.isFinite, duration > 0 else { return false }
        return state.time >= duration - Self.finishEpsilon
    }

    @ViewBuilder
    private func finishVerdictBanner(rival: ReplayRival, result: ReplayRaceResult) -> some View {
        let text = verdictText(rival: rival, result: result)
        ReplayFinishVerdictView(
            verdict: text,
            shareItem: shareCardItem,
            saveReport: { saveRaceReport(rival: rival, result: result) },
            saveCard: { saveRaceCard(rival: rival, result: result) },
            retrySharePreparation: { prepareShareCard(rival: rival, result: result) }
        )
    }

    private func verdictText(rival: ReplayRival, result: ReplayRaceResult) -> String {
        let rivalDescription = verdictRivalDescription(rival)
        if result.rivalDidNotFinish {
            let shortfall = result.distanceMargin.map {
                RowPlayFormatting.distance($0, unit: unit)
            } ?? "—"
            return "You win against \(rivalDescription). Rival did not finish (\(shortfall) short)."
        }

        let timePart: String = {
            if let t = result.timeMargin, t > Self.finishEpsilon {
                return " by \(String(format: "%.1f", t))s"
            }
            return ""
        }()
        let distancePart: String = {
            if let d = result.distanceMargin, d > 0.5 {
                return " (\(RowPlayFormatting.distance(d, unit: unit)))"
            }
            return ""
        }()

        switch result.outcome {
        case .playerWon:
            return "You beat \(rivalDescription)\(timePart)\(distancePart)."
        case .rivalWon:
            return "\(rivalDescription) beat you\(timePart)\(distancePart)."
        case .tie:
            return "Tie with \(rivalDescription)."
        }
    }

    private func verdictRivalDescription(_ rival: ReplayRival) -> String {
        switch rival.kind {
        case .session:
            if let id = rival.sessionWorkoutID,
               let candidate = ghostCandidateByID[id] {
                let date = candidate.workout.date.formatted(Self.candidateDateStyle.locale(currentLocale))
                return "your \(date) session"
            }
            return "your past session"
        case .constantPace:
            if let pace = rival.targetPace {
                return "the \(RowPlayFormatting.pace(pace)) pace boat"
            }
            return "the pace boat"
        case .importedFile:
            // Live UI may show filename; exported wording uses "Imported rival".
            if let name = rival.localFileName {
                return name
            }
            return "the imported rival"
        }
    }

    private func makeReport(rival: ReplayRival, result: ReplayRaceResult) -> ReplayRaceReport {
        let sessionDate: Date? = {
            guard let id = rival.sessionWorkoutID else { return nil }
            return ghostCandidateByID[id]?.workout.date
        }()
        return ReplayRaceReportBuilder.build(
            player: detail.workout,
            rival: rival,
            result: result,
            sessionDate: sessionDate
        )
    }

    private func saveRaceReport(rival: ReplayRival, result: ReplayRaceResult) {
        do {
            let report = makeReport(rival: rival, result: result)
            let data = try ReplayRaceReportCodec.encode(report)
            exportReportItem = ReplayRaceReportTransferItem(
                data: data,
                suggestedName: ReplayRaceSuggestedFilename.report
            )
            rivalErrorMessage = nil
            showReportExporter = true
        } catch {
            rivalErrorMessage = "Could not encode race report"
        }
    }

    private func saveRaceCard(rival: ReplayRival, result: ReplayRaceResult) {
        let report = makeReport(rival: rival, result: result)
        guard let png = ReplayRaceCardRenderer.renderPNG(report: report, colorScheme: colorScheme) else {
            rivalErrorMessage = "Could not render race card"
            return
        }
        exportCardItem = ReplayRaceCardTransferItem(
            data: png,
            suggestedName: ReplayRaceSuggestedFilename.card
        )
        rivalErrorMessage = nil
        showCardExporter = true
    }

    private func prepareShareCard(rival: ReplayRival, result: ReplayRaceResult) {
        let report = makeReport(rival: rival, result: result)
        guard let png = ReplayRaceCardRenderer.renderPNG(report: report, colorScheme: colorScheme) else {
            rivalErrorMessage = "Could not render race card"
            return
        }
        shareCardItem = ReplayRaceCardTransferItem(
            data: png,
            suggestedName: ReplayRaceSuggestedFilename.card
        )
        rivalErrorMessage = nil
    }

    private func prepareShareCardIfFinished() {
        guard showsFinishVerdict,
              shareCardItem == nil,
              let rival = activeRival,
              let result = cachedRaceResult else {
            return
        }
        prepareShareCard(rival: rival, result: result)
    }

    static func isUserCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    // MARK: - Replay Surface

    @ViewBuilder
    private var replaySurface: some View {
        switch rendererMode {
        case .twoD:
            twoDReplaySurface
        case .threeD:
            RealityReplaySceneView(
                detail: detail,
                state: $state,
                reduceMotion: reduceMotion,
                rival: activeRival,
                selectedQuality: preferences.replayRenderQuality,
                effectiveQuality: Binding(
                    get: { displayedEffectiveReplayQuality },
                    set: { effectiveReplayQuality = $0 }
                ),
                cameraPreset: cameraPreset,
                cameraResetGeneration: cameraResetGeneration,
                replayDiscontinuityGeneration: replayDiscontinuityGeneration
            )
            .id(Replay3DViewIdentity(
                workoutID: detail.id,
                sportRawValue: detail.workout.sport.rawValue
            ))
            .frame(minHeight: 300)
        }
    }

    private var qualityPicker: some View {
        HStack(spacing: AppDesign.Spacing.small) {
            Picker(selection: Binding(
                get: { preferences.replayRenderQuality.rawValue },
                set: { rawValue in
                    guard let quality = ReplayRenderQuality(rawValue: rawValue) else { return }
                    effectiveReplayQuality = quality
                    preferences.replayRenderQuality = quality
                }
            )) {
                ForEach(ReplayRenderQuality.allCases, id: \.rawValue) { quality in
                    Text(quality.replayDisplayName).tag(quality.rawValue)
                }
            } label: {
                Label(Self.qualityAccessibilityLabel, systemImage: "slider.horizontal.3")
            }
            .pickerStyle(.menu)
            .labelStyle(.iconOnly)
            .accessibilityLabel(Self.qualityAccessibilityLabel)
            .accessibilityValue(Self.qualityAccessibilityValue(
                selected: preferences.replayRenderQuality,
                effective: displayedEffectiveReplayQuality
            ))
            #if os(macOS)
            .help(Self.qualityPickerHelp)
            #endif

            if Self.isAdaptiveReduction(
                selected: preferences.replayRenderQuality,
                effective: displayedEffectiveReplayQuality
            ) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Self.adaptiveQualityAccessibilityLabel(
                        effective: displayedEffectiveReplayQuality
                    ))
                    #if os(macOS)
                    .help(Self.adaptiveQualityHelp)
                    #endif
            }
        }
    }

    static func qualityAccessibilityValue(
        selected: ReplayRenderQuality,
        effective: ReplayRenderQuality
    ) -> String {
        "Selected \(selected.replayDisplayName), effective \(effective.replayDisplayName)"
    }

    static func adaptiveQualityAccessibilityLabel(
        effective: ReplayRenderQuality
    ) -> String {
        "3D replay quality reduced to \(effective.replayDisplayName)"
    }

    static func showsQualityControl(rendererMode: ReplayRendererMode) -> Bool {
        rendererMode == .threeD
    }

    static func isAdaptiveReduction(
        selected: ReplayRenderQuality,
        effective: ReplayRenderQuality
    ) -> Bool {
        effective.maximumDegradationLevel < selected.maximumDegradationLevel
    }

    static func effectiveQualityForDisplay(
        selected: ReplayRenderQuality,
        reportedEffective: ReplayRenderQuality?
    ) -> ReplayRenderQuality {
        reportedEffective ?? selected
    }

    private var displayedEffectiveReplayQuality: ReplayRenderQuality {
        Self.effectiveQualityForDisplay(
            selected: preferences.replayRenderQuality,
            reportedEffective: effectiveReplayQuality
        )
    }

    private var twoDReplaySurface: some View {
        let interval = reduceMotion ? 1.0 / 15.0 : 1.0 / 60.0
        return TimelineView(.animation(minimumInterval: interval, paused: !state.playing)) { timelineContext in
            replayCanvas
                .onChange(of: timelineContext.date) { oldDate, newDate in
                    guard state.playing else {
                        lastTickDate = newDate
                        return
                    }
                    let tick = ReplayPlaybackClock.tick(
                        lastTickDate: lastTickDate,
                        currentDate: newDate
                    )
                    lastTickDate = tick.lastTickDate
                    state.tick(deltaTime: tick.delta)
                }
        }
        .frame(minHeight: 300)
    }

    // MARK: - Canvas

    private var replayCanvas: some View {
        Canvas { context, size in
            context.stroke(ghostStrokePath, with: .color(AppDesign.softPurple.opacity(0.35)), lineWidth: 1.5)
            context.stroke(strokePath, with: .color(cachedMachineColor.opacity(0.7)), lineWidth: 2)
            drawGhostPlayhead(in: &context, size: size)
            drawPlayhead(in: &context, size: size)
        }
        .accessibilityLabel("Workout replay timeline")
        .accessibilityValue(canvasAccessibilityValue)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size, initial: true) { _, newSize in
                        canvasSize = newSize
                        strokePath = self.makeStrokePath(strokes: detail.strokes, size: newSize)
                        if let rival = activeRival {
                            ghostStrokePath = makeGhostStrokePath(
                                ghostStrokes: rival.strokes,
                                playerStrokes: detail.strokes,
                                size: newSize
                            )
                        }
                    }
            }
        )
        .onAppear {
            cachedMachineColor = Self.machineColor(for: detail.workout.sport, colorScheme: colorScheme)
        }
        .onChange(of: colorScheme) { _, scheme in
            cachedMachineColor = Self.machineColor(for: detail.workout.sport, colorScheme: scheme)
        }
        .onChange(of: detail.id) { _, _ in
            strokePath = self.makeStrokePath(strokes: detail.strokes, size: canvasSize)
            cachedMachineColor = Self.machineColor(for: detail.workout.sport, colorScheme: colorScheme)
            // Drop non-session or missing session rivals when the workout changes.
            if let rival = activeRival, rival.kind == .session {
                if let id = rival.sessionWorkoutID,
                   ghostCandidateByID[id] == nil {
                    selectRival(nil)
                }
            }
            ghostStrokePath = Path()
            if canvasSize != .zero, let rival = activeRival {
                ghostStrokePath = makeGhostStrokePath(
                    ghostStrokes: rival.strokes,
                    playerStrokes: detail.strokes,
                    size: canvasSize
                )
            }
            if let rival = activeRival {
                cachedRaceResult = ReplayRaceResultCalculator.result(
                    playerStrokes: detail.strokes,
                    rivalStrokes: rival.strokes,
                    workout: detail.workout
                )
            } else {
                cachedRaceResult = nil
            }
        }
    }

    private func drawPlayhead(in context: inout GraphicsContext, size: CGSize) {
        let duration = state.duration
        let maxD = detail.strokes.last?.d ?? 1
        guard duration.isFinite, duration > 0, maxD.isFinite, maxD > 0 else { return }
        let frame = state.currentFrame

        let x = unitFraction(frame.t, denominator: duration) * size.width
        let y = size.height - unitFraction(frame.d, denominator: maxD) * size.height

        var playhead = Path()
        playhead.move(to: CGPoint(x: x, y: 0))
        playhead.addLine(to: CGPoint(x: x, y: size.height))
        let playheadColor = AppDesign.alertRed
        context.stroke(playhead, with: .color(playheadColor), lineWidth: 1)

        let dotSize: CGFloat = 8
        let dot = Path(ellipseIn: CGRect(
            x: x - dotSize / 2,
            y: y - dotSize / 2,
            width: dotSize,
            height: dotSize
        ))
        context.fill(dot, with: .color(playheadColor))
    }

    private func drawGhostPlayhead(in context: inout GraphicsContext, size: CGSize) {
        guard let rival = activeRival, !rival.strokes.isEmpty else { return }
        let duration = state.duration
        let maxD = detail.strokes.last?.d ?? 1
        guard duration.isFinite, duration > 0, maxD.isFinite, maxD > 0 else { return }

        let ghostDist = ReplayRaceGap.ghostDistance(elapsed: state.time, strokes: rival.strokes)
        guard ghostDist.isFinite, ghostDist >= 0 else { return }

        let x = unitFraction(state.time, denominator: duration) * size.width
        let y = size.height - unitFraction(ghostDist, denominator: maxD) * size.height

        let ghostColor = AppDesign.softPurple
        let dotSize: CGFloat = 8
        let dot = Path(ellipseIn: CGRect(
            x: x - dotSize / 2,
            y: y - dotSize / 2,
            width: dotSize,
            height: dotSize
        ))
        let strokeDot = Path(ellipseIn: CGRect(
            x: x - dotSize / 2 - 1,
            y: y - dotSize / 2 - 1,
            width: dotSize + 2,
            height: dotSize + 2
        ))
        context.stroke(strokeDot, with: .color(cachedMachineColor.opacity(0.3)), lineWidth: 1)
        context.fill(dot, with: .color(ghostColor.opacity(0.8)))
    }

    private func unitFraction(_ numerator: Double, denominator: Double) -> CGFloat {
        guard numerator.isFinite, denominator.isFinite, denominator > 0 else { return 0 }
        return CGFloat(max(0, min(1, numerator / denominator)))
    }

    /// Precomputes the full stroke trail path so the Canvas draw closure only strokes it.
    func makeStrokePath(strokes: [Stroke], size: CGSize) -> Path {
        guard strokes.count > 1 else { return Path() }

        let originT = strokes[0].t
        let maxT = strokes.last?.t ?? originT
        let maxD = strokes.last?.d ?? 1
        let duration = maxT - originT
        guard duration.isFinite, duration > 0, maxD.isFinite, maxD > 0 else { return Path() }

        var path = Path()
        for (i, stroke) in strokes.enumerated() {
            let x = unitFraction(stroke.t - originT, denominator: duration) * size.width
            let y = size.height - unitFraction(stroke.d, denominator: maxD) * size.height
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    /// Precomputes the ghost stroke trail path using player chart scales
    /// for direct comparability.
    func makeGhostStrokePath(
        ghostStrokes: [Stroke],
        playerStrokes: [Stroke],
        size: CGSize
    ) -> Path {
        ReplayRivalPathBuilder.makePath(
            ghostStrokes: ghostStrokes,
            playerStrokes: playerStrokes,
            size: size
        )
    }

    private var canvasAccessibilityValue: String {
        let frame = state.currentFrame
        var parts: [String] = [
            "Time \(RowPlayFormatting.time(frame.t, tenths: true))",
            "Distance \(RowPlayFormatting.distance(frame.d, unit: unit))"
        ]
        if let rival = activeRival {
            let ghostDist = ReplayRaceGap.ghostDistance(elapsed: state.time, strokes: rival.strokes)
            let gapM = ReplayRaceGap.raceGapMeters(playerDistance: frame.d, ghostDistance: ghostDist)
            parts.append(gapLabel(meters: gapM))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Telemetry

    private var telemetryBar: some View {
        HStack(spacing: AppDesign.Spacing.xLarge) {
            TelemetryItem(label: "Time", value: RowPlayFormatting.time(state.currentFrame.t, tenths: true), color: AppDesign.MetricColor.duration)
            TelemetryItem(label: "Distance", value: RowPlayFormatting.distance(state.currentFrame.d, unit: unit), color: AppDesign.MetricColor.distance)
            TelemetryItem(label: "Pace", value: RowPlayFormatting.pace(state.currentFrame.pace), color: AppDesign.MetricColor.pace)
            TelemetryItem(label: detail.workout.sport.cadenceUnit, value: cadenceText, color: AppDesign.MetricColor.cadence)
            TelemetryItem(label: "Watts", value: "\(state.currentFrame.watts)", color: AppDesign.MetricColor.watts)
            if let hr = state.currentFrame.heartRate {
                TelemetryItem(label: "HR", value: "\(hr)", color: AppDesign.MetricColor.heartRate)
            }
        }
        .padding(.vertical, AppDesign.Spacing.medium)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    private var cadenceText: String {
        guard state.currentFrame.cadence.isFinite else { return "-" }
        return String(Int(state.currentFrame.cadence.rounded()))
    }

    static func machineColor(for sport: Sport, colorScheme: ColorScheme) -> Color {
        let color = ReplaySportThemeLookup.machineColor(for: sport)
        return Color(hex: colorScheme == .dark ? color.dark : color.light)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        let playPauseLabel: LocalizedStringKey = state.playing ? "Pause replay" : "Play replay"

        return HStack(spacing: AppDesign.Spacing.xLarge) {
            PlayPauseButton(isPlaying: state.playing, action: { state.toggle() })
                .accessibilityLabel(playPauseLabel)
                #if os(macOS)
                .help(playPauseLabel)
                #endif
                .keyboardShortcut(.space, modifiers: [])

            Slider(
                value: Binding(
                    get: { state.time },
                    set: { newTime in
                        if newTime != state.time {
                            replayDiscontinuityGeneration &+= 1
                        }
                        state.seek(to: newTime)
                    }
                ),
                in: 0...max(state.duration, 1),
                onEditingChanged: { isEditing in
                    if isEditing { state.pause() }
                }
            )
            .tint(AppDesign.MetricColor.pace)
            .accessibilityLabel("Replay progress")
            .accessibilityValue("\(RowPlayFormatting.time(state.time, tenths: true)) of \(RowPlayFormatting.time(state.duration, tenths: true))")

            Picker("Speed", selection: Binding(
                get: { state.speed },
                set: { state.setSpeed($0) }
            )) {
                ForEach(ReplaySpeed.allCases, id: \.self) { speed in
                    Text(speed.label).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
        .padding()
    }
}

struct Replay3DSceneIdentity: Hashable {
    let workoutID: Int
    let rivalID: String?
    let sportRawValue: String
}

/// Stable owner identity for camera, orbit, adaptive-quality, and cached live
/// workout aggregates. Rival changes intentionally do not replace this owner;
/// a different workout or sport does.
struct Replay3DViewIdentity: Hashable {
    let workoutID: Int
    let sportRawValue: String
}

// MARK: - Play/Pause Button

private struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(isHovering ? Color.accentColor.opacity(0.16) : AppDesign.activeCardBackground)
                )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        #endif
    }
}

/// Shared timeline clock for replay surfaces. Resetting the date on resume
/// makes the first post-pause tick deterministic rather than including the
/// elapsed wall-clock pause duration.
struct ReplayPlaybackTick {
    let rawDelta: TimeInterval?
    let delta: TimeInterval
    let lastTickDate: Date
}

enum ReplayPlaybackClock {
    static func tick(lastTickDate: Date?, currentDate: Date) -> ReplayPlaybackTick {
        guard let lastTickDate else {
            return ReplayPlaybackTick(rawDelta: nil, delta: 0, lastTickDate: currentDate)
        }
        let rawDelta = currentDate.timeIntervalSince(lastTickDate)
        return ReplayPlaybackTick(
            rawDelta: rawDelta,
            delta: ReplayMotion.clampDt(ms: rawDelta * 1_000),
            lastTickDate: currentDate
        )
    }
}

// MARK: - Telemetry Item

private struct TelemetryItem: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: AppDesign.Spacing.xxSmall) {
            Text(value)
                .font(AppDesign.Typography.metricValue.monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(AppDesign.Typography.compactLabel)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .accentColor
            return
        }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

extension ReplayRenderQuality {
    var replayDisplayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .ultra: "Ultra"
        }
    }
}
