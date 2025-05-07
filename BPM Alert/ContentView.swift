//
//  ContentView.swift
//  BPM Alert
//
//  Created by Mark Jeschke on 5/3/25.
//

import SwiftUI
import AudioKit
import AudioKitEX
import AVFAudio

class MetronomeConductor: ObservableObject {
    let engine = AudioEngine()
    var instrument = AppleSampler()
    var sequencer = Sequencer()
    var midiCallback: CallbackInstrument!
    
    @Published var isPlaying: Bool = false
    @Published var currentBeat: Int = 0
    @Published var beatsPerBar: Int = 4

    @Published var tempo: Double = 120.0 {
        didSet {
            sequencer.tempo = BPM(tempo)
        }
    }
    
    @Published var volume: Double = 1.0 {
        didSet {
            instrument.volume = 0.5 + Float(volume) * 0.5
        }
    }
        
    func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
        isPlaying.toggle()
    }
    
    func startPlayback() {
        sequencer.playFromStart()
    }
    
    func stopPlayback() {
        sequencer.stop()
        currentBeat = 0
    }
    
    init() {
        midiCallback = CallbackInstrument { status, note, vel in
            if status == 144 { // Note On
                DispatchQueue.main.async {
                    if self.currentBeat >= self.beatsPerBar {
                        self.currentBeat = 0
                    }
                    self.currentBeat += 1
                }
            }
        }
        
        engine.output = PeakLimiter(Mixer(instrument, midiCallback), attackTime: 0.001, decayTime: 0.001, preGain: 0)
        
        _ = sequencer.addTrack(for: instrument)
        _ = sequencer.addTrack(for: midiCallback)
        
        loadInstrument()
        updateSequencer()
    }

    func loadInstrument() {
        do {
            if let accentURL = Bundle.main.url(forResource: "accent_C1", withExtension: "wav") {
                let accentFile = try AVAudioFile(forReading: accentURL)
                try instrument.loadAudioFiles([accentFile])
            } else {
                Log("Could not find audio files")
            }
        } catch {
            Log("Files Didn't Load: \(error)")
        }
    }

    func updateSequencer() {
        for track in sequencer.tracks {
            track.length = Double(beatsPerBar)
            track.clear()
            track.loopEnabled = true
            track.add(noteNumber: 24, velocity: 127, position: 0.0, duration: 0.2)
            
            for beat in 1 ..< beatsPerBar {
                track.add(noteNumber: 24, velocity: 70, position: Double(beat), duration: 0.2)
            }
        }
        currentBeat = 0
        if isPlaying {
            sequencer.playFromStart()
        }
    }
    
    func start() {
        do {
            try engine.start()
        } catch {
            print("AudioKit error: \(error)")
        }
    }
    
    func stop() {
        engine.stop()
    }
}

struct MetronomeView: View {
    @StateObject var conductor = MetronomeConductor()
    @Environment(\.scenePhase) private var scenePhase

    private let defaultTempo: Double = 120
    
    // Volume Level: Most are calculated as Double values, such as 0.0-1.0. For the displayed text, it's converted to percentage as 0-100%.
    @AppStorage("volumeLevel") private var volumeLevel: Double = 1.0 {
        didSet {
            conductor.volume = volumeLevel
        }
    }
    
    @AppStorage("bpmNumber") private var bpmNumber: Double = 120 {
        didSet {
            conductor.tempo = bpmNumber
        }
    }
    
    @State private var bpmText: String = ""
    @State private var showAlert: Bool = false
    @State private var isBPMRangeValid: Bool = false
    @State private var alertTitle: String = "Change BPM"
    private let minBPM: Double = 30
    private var minBPMText: String {
        String(format: "%.f", minBPM)
    }
    private let maxBPM: Double = 500
    private var maxBPMText: String {
        String(format: "%.f", maxBPM)
    }
    private var numberRange: ClosedRange<Double> {
        minBPM...maxBPM
    }
    private var rangeText: String {
        String(format: "%.f - %.f", minBPM, maxBPM)
    }
    private let characterLimit = 3

    // Tap Tempo
    @GestureState private var isTapTempoTapped = false
    @State private var tapTimes: [TimeInterval] = []
    private let maxTapInterval: TimeInterval = 2.0
    private let minTapAmount: Int = 3
    @State private var isTapTempoButtonPressed: Bool = false

    @GestureState private var isToggleMetronomeButtonTapped = false
    @State private var isToggleMetronomeButtonPressed: Bool = false

    private var volumeLevelText: String {
        String(format: "%.f", volumeLevel * 100)
    }
    @State private var lastVolumeLevel: Double = 0.5
    @State private var isMuted = false
    private let defaultVolumeLevel: Double = 0.5
    private let minVolumeLevel: Double = 0.0
    private var minVolumeLevelText: String {
        String(format: "%.f", minVolumeLevel * 100)
    }
    private let maxVolumeLevel: Double = 1.0
    private var maxVolumeLevelText: String {
        String(format: "%.f", maxVolumeLevel * 100)
    }

    // MARK: ------ Main Content Layout ------
    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                BeatIndicatorRow(beatsPerBar: $conductor.beatsPerBar, currentBeat: conductor.currentBeat)
                timeSignatureButtons(beatsPerBar: $conductor.beatsPerBar, updateSequencer: conductor.updateSequencer)
                bpmTextAlertButton
                bpmSliderButtons
                volumeSliderButtons
                tapTempoButton
                toggleMetronomeButton
            }
            .padding()
            .onAppear {
                lastVolumeLevel = volumeLevel
                conductor.tempo = bpmNumber
                conductor.volume = volumeLevel
                conductor.start()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    if !self.conductor.engine.avEngine.isRunning {
                        self.conductor.start()
                        self.conductor.loadInstrument()
                    }
                } else if newPhase == .background {
                    conductor.stop()
                    conductor.sequencer.stop()
                }
            }
            .animation(.bouncy, value: bpmNumber)
            .animation(.bouncy, value: isTapTempoButtonPressed)
            .animation(.bouncy, value: volumeLevel)
        }
    }
    
    //MARK: ------ Beat Indicator Views ------
    struct timeSignatureButtons: View {
        @Binding var beatsPerBar: Int
        var updateSequencer: () -> Void
        
        var body: some View {
            VStack(spacing: 5) {
                Text("Time Signature".uppercased())
                    .font(.headline)
                    .fontWeight(.bold)
                HStack {
                    Button {
                        beatsPerBar = max(1, beatsPerBar - 1)
                        updateSequencer()
                    } label: {
                        Image(systemName: "minus")
                            .aspectRatio(contentMode: .fit)
                            .font(.system(size: 25.0, weight: .regular, design: .rounded))
                    }
                    .frame(width: 44, height: 44)
                    .accessibility(label: Text("Decrease the beats per bar by 1."))
                    .disabled(beatsPerBar <= 1)
                    
                    Text("\(beatsPerBar)/4")
                        .contentTransition(.numericText(value: Double(beatsPerBar)))
                        .font(.headline)
                        .fontWeight(.bold)
                        .frame(width: 60)
                        .animation(.snappy, value: beatsPerBar)
                    
                    Button {
                        beatsPerBar = min(8, beatsPerBar + 1)
                        updateSequencer()
                    } label: {
                        Image(systemName: "plus")
                            .aspectRatio(contentMode: .fit)
                            .font(.system(size: 25.0, weight: .regular, design: .rounded))
                    }
                    .frame(width: 44, height: 44)
                    .accessibility(label: Text("Increase the beats per bar by 1."))
                    .disabled(beatsPerBar >= 8)
                }
            }
        }
    }
    
    //MARK: ------ Beat Indicator Views ------
    struct BeatIndicatorRow: View {
        @Binding var beatsPerBar: Int
        let currentBeat: Int

        var body: some View {
            HStack(spacing: 15) {
                ForEach(1...beatsPerBar, id: \.self) { beatNumber in
                    BeatIndicator(
                        beatNumber: beatNumber,
                        currentBeat: currentBeat
                    )
                }
            }
            .padding(.horizontal)
            .frame(height: 40)
            .animation(.spring(duration: 0.3), value: beatsPerBar)

        }
    }

    struct BeatIndicator: View {
        let beatNumber: Int
        let currentBeat: Int

        var body: some View {
            HStack {
                Circle()
                    .fill(beatNumber == currentBeat ?
                          Color.blue :
                            Color.gray.opacity(0.3))
                    .frame(height: beatNumber == currentBeat ? 30 : 20)
                    .overlay(
                        Circle()
                            .stroke(Color.blue, lineWidth: 1)
                    )
                    .animation(.snappy, value: currentBeat)
            }
            .frame(width: 30)
        }
    }

    //MARK: ------ Extracted Button Views ------

    private var bpmTextAlertButton: some View {
        Button {
            bpmText = ""
            showAlert.toggle()
        } label: {
            Text("\(bpmNumber, specifier: "%.f")")
                .padding()
                .frame(minWidth: 170)
                .background(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.secondary, lineWidth: 1)
                }
                .font(.system(size: 65, design: .rounded))
                .fontWeight(.light)
                .contentTransition(.numericText(value: Double(bpmNumber)))
                .gesture(DragGesture()
                    .onChanged { value in
                        let change = value.translation.width / 5
                        adjustTempo(by: change)
                    })
                .overlay {
                    VStack {
                        Image(systemName: "chevron.up")
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .padding(10)
                    .foregroundStyle(.secondary)
                }
        }
        .tint(.primary)

        //MARK: Alert View
        .alert(
            Text(alertTitle),
            isPresented: $showAlert
        ) {
            Button("Cancel") { }
            Button("OK") {
                if !bpmText.isEmpty {
                    withAnimation {
                        bpmNumber = Double(bpmText) ?? defaultTempo
                    }
                }
            }
            .disabled(!isBPMRangeValid) // <- Disable OK button if the number entered is not within the range.

            //MARK: TextField
            TextField("BPM", text: $bpmText, prompt: Text("\(String(format: "%.f", bpmNumber))").foregroundStyle(.secondary))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .onChange(of: bpmText) { _, newValue in
                    // Don't allow more than 3 text characters to be entered into the input field.
                    if newValue.count > characterLimit {
                        bpmText = String(newValue.prefix(characterLimit))
                    } else {
                        if showAlert {
                            if newValue.count > 1 {
                                if let tempNumber = Double(newValue) {
                                    if numberRange.contains(tempNumber) {
                                        isBPMRangeValid = true
                                        print("BPM within \(rangeText) range")
                                    } else {
                                        isBPMRangeValid = false
                                        print("BPM outside of \(rangeText) range")
                                    }
                                }
                            } else {
                                isBPMRangeValid = false
                                print("Waiting for more numbers...")
                            }
                        }
                    }
                }
        } message: {
            Text(rangeText)
        }
        .accessibility(label: Text("Enter the beats per minute (BPM) numerically."))
    }

    //MARK: Tempo sliders & buttons
    private var bpmSliderButtons: some View {
        VStack(spacing: 5) {
            Text("Tempo".uppercased())
                .font(.headline)
                .fontWeight(.bold)
            HStack {
                Button {
                    decreaseTempo()
                } label: {
                    Image(systemName: "minus")
                        .aspectRatio(contentMode: .fit)
                        .font(.system(size: 25.0, weight: .regular, design: .rounded))
                }
                .frame(width: 44, height: 44)
                .accessibility(label: Text("Decrease the tempo by 1."))
                .disabled(bpmNumber <= minBPM)
                Slider(value: $bpmNumber, in: minBPM...maxBPM) {
                    Text("BPM")
                } minimumValueLabel: {
                    Text(minBPMText)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text(maxBPMText)
                        .foregroundStyle(.secondary)
                }
                .onTapGesture(count: 2) {
                    withAnimation {
                        bpmNumber = defaultTempo
                    }
                }
                Button {
                    increaseTempo()
                } label: {
                    Image(systemName: "plus")
                        .aspectRatio(contentMode: .fit)
                        .font(.system(size: 25.0, weight: .regular, design: .rounded))
                }
                .frame(width: 44, height: 44)
                .accessibility(label: Text("Increase the tempo by 1."))
                .disabled(bpmNumber >= maxBPM)
            }
            .onChange(of: bpmNumber, { _, newValue in
                bpmText = String(format: "%.f", newValue)
                conductor.tempo = newValue
            })
        }
    }

    //MARK: Volume slider buttons
    private var volumeSliderButtons: some View {
        VStack(spacing: 5) {
            Text("Volume:  \(volumeLevelText)".uppercased())
                .contentTransition(.numericText(value: volumeLevel))
                .font(.headline)
                .fontWeight(.bold)
                .frame(maxWidth: 155, alignment: .leading)
                .offset(x: 20)
            HStack {
                Button(action: {
                    withAnimation {
                        isMuted.toggle()
#if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                        volumeLevel = isMuted ? 0 : lastVolumeLevel
                    }
                }, label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.slash")
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.accentColor)
                        .font(.system(size: 25.0, weight: .light, design: .rounded))
                })
                .frame(width: 44, height: 44)
                .accessibility(label: Text("Mute the metronome completely."))
                .accessibility(value: Text("The volume is set to \(Int(lastVolumeLevel)) out of 100."))


                Slider(value: $volumeLevel, in: minVolumeLevel...maxVolumeLevel) {
                    Text("Volume Level")
                } minimumValueLabel: {
                    Text(minVolumeLevelText)
                } maximumValueLabel: {
                    Text(maxVolumeLevelText)
                }
                .foregroundStyle(.secondary)
                .onChange(of: volumeLevel, { oldValue, newValue in
                    withAnimation {
                        if newValue > minVolumeLevel && newValue < maxVolumeLevel {
                            lastVolumeLevel = volumeLevel
                        }
                        isMuted = newValue <= minVolumeLevel
                        conductor.volume = newValue
                    }
                })
                .onTapGesture(count: 2) {
                    withAnimation {
                        volumeLevel = defaultVolumeLevel
                    }
                }
                Button(action: {
                    withAnimation {
                        volumeLevel = volumeLevel < maxVolumeLevel ? maxVolumeLevel : lastVolumeLevel
                        isMuted = false
                    }
#if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                }, label: {
                    Image(systemName: !isMuted ? "speaker.wave.3.fill" : "speaker.wave.3")
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.accentColor)
                        .font(.system(size: 25.0, weight: .light, design: .rounded))
                })
                .frame(width: 44, height: 44)
                .accessibility(label: Text("Turn sound on 100%."))
                .accessibility(value: Text("The volume is set to \(Int(lastVolumeLevel)) out of 100."))
            }
        }
    }

    //MARK: Toggle Metronome button
    private var toggleMetronomeButton: some View {
        let tap = DragGesture(minimumDistance: 0)
            .onEnded({ isTapped in
                withAnimation(.easeIn(duration: 0.4)) {
                    isToggleMetronomeButtonPressed = false
                }
            })
            .updating($isToggleMetronomeButtonTapped) { (_, isTapped, _) in
                if !isTapped && !isToggleMetronomeButtonPressed {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                    withAnimation(.easeOut(duration: 0.1)) {
                        isToggleMetronomeButtonPressed = true
                    }
                    conductor.togglePlayback()
                }
            }

        return HStack {
            HStack {
                Circle()
                    .foregroundStyle(isToggleMetronomeButtonPressed ? .white.opacity(0.4) : .clear)
                    .background(.thinMaterial)
                    .overlay {
                        Image(systemName: conductor.isPlaying ? "stop.fill" : "play.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(.white)
                            .frame(maxWidth: 25, maxHeight: 25)
                            .contentTransition(.symbolEffect(.replace, options: .speed(6)))
                            .offset(x: conductor.isPlaying ? 0 : 3)
                    }
            }
            .foregroundStyle(.clear)
            .frame(maxWidth: 80, maxHeight: 80)
            .clipShape(Circle())
            .scaleEffect(isToggleMetronomeButtonPressed ? 0.94 : 1)
            .gesture(tap)
            .accessibility(label: Text("Toggle Metronome button"))
        }
    }

    //MARK: Tap Tempo buttons
    private var tapTempoButton: some View {
        let tap = DragGesture(minimumDistance: 0)
            .onEnded({ isTapped in
                withAnimation {
                    isTapTempoButtonPressed = false
                }
            })
            .updating($isTapTempoTapped) { (_, isTapped, _) in
                if !isTapped && !isTapTempoButtonPressed {
                    withAnimation {
                        isTapTempoButtonPressed = true
                        handleTapTempoTaps()
                    }
    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    #endif
                }
            }

        return HStack {
            HStack {
                Text("Tap Tempo")
                Image(systemName: "hand.tap.fill")
            }
            .foregroundStyle(.white)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .shadow(radius: 8)
            .padding()
            .frame(maxWidth: 200, maxHeight: 50)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isTapTempoButtonPressed ? Color.blue.opacity(0.5) : Color.blue)
            }
            .scaleEffect(isTapTempoButtonPressed ? 0.95 : 1)
            .gesture(tap)
            .accessibility(label: Text("Tap Tempo button"))
        }
    }


    //MARK: Tempo adustment buttons
    private func increaseTempo() {
        if bpmNumber < maxBPM {
            withAnimation {
                bpmNumber += 1
#if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
            }
        }
    }

    private func decreaseTempo() {
        if bpmNumber > minBPM {
            withAnimation {
                bpmNumber -= 1
#if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
            }
        }
    }

    //MARK: Swipeable tempo calculations
    private func adjustTempo(by amount: Double) {
        bpmNumber = max(minBPM, min(maxBPM, bpmNumber + amount))
    }

    //MARK: Tap Tempo calculations
    private func handleTapTempoTaps() {
        let now = Date().timeIntervalSince1970
        tapTimes.append(now)

        tapTimes = tapTimes.filter {
            now - $0 < maxTapInterval
        }

        guard tapTimes.count >= minTapAmount else { return }

        let intervals = zip(tapTimes, tapTimes.dropFirst()).map(-)
        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        let bpm = abs(60.0 / avgInterval)

        if bpm >= minBPM && bpm <= maxBPM {
            bpmNumber = bpm
        }
    }
}

#Preview {
    MetronomeView()
}
