//
//  ContentView.swift
//  BPM Alert
//
//  Created by Mark Jeschke on 5/3/25.
//

import SwiftUI

struct ContentView: View {
    private let defaultTempo: Double = 120
    @AppStorage("bpmNumber") private var bpmNumber: Double = 120
    @State private var bpmText: String = ""
    @State private var showAlert: Bool = false
    @State private var isBPMRangeValid: Bool = false
    @State private var alertTitle: String = "Change BPM"
    private let minBPM: Double = 30
    private var minBPMText: String {
        String(format: "%.f", minBPM)
    }
    private let maxBPM: Double = 400
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

    // Volume Level: Most are calculated as Double values, such as 0.0-1.0. For the displayed text, it's converted to percentage as 0-100%.
    @AppStorage("volumeLevel") private var volumeLevel: Double = 0.5
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

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            bpmTextAlert
            bpmSliderButtons
            volumeSliderButtons
            Spacer()
            tapTempoButton
        }
        .padding()
        .onAppear {
            lastVolumeLevel = volumeLevel
        }
        .animation(.bouncy, value: bpmNumber)
        .animation(.bouncy, value: isTapTempoButtonPressed)
        .animation(.bouncy, value: volumeLevel)
    }

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

    private var bpmTextAlert: some View {
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

    private func adjustTempo(by amount: Double) {
        bpmNumber = max(minBPM, min(maxBPM, bpmNumber + amount))
    }

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
            })
        }
    }

    private var volumeSliderButtons: some View {
        VStack(spacing: 5) {
            Text("Volume Level:  \(volumeLevelText)".uppercased())
                .contentTransition(.numericText(value: volumeLevel))
                .font(.headline)
                .fontWeight(.bold)
                .frame(maxWidth: 180, alignment: .leading)
                .offset(x: 5)
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

    private var tapTempoButton: some View {
        let tap = DragGesture(minimumDistance: 0)
            .onEnded({ isTapped in
                withAnimation {
                    isTapTempoButtonPressed = false
                }
            })
            .updating($isTapTempoTapped) { (_, isTapped, _) in
                withAnimation {
                    isTapTempoButtonPressed = true
                    handleTap()
                }
#if os(iOS)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
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

    private func handleTap() {
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
    ContentView()
}

struct CapsuleButtonStyle: ButtonStyle {
    var bgColor: Color
    var tapBgColor: Color

    func simpleSuccess() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .padding(10)
            .frame(height: 44, alignment: .center)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(configuration.isPressed ? tapBgColor : bgColor)
                }
            )
            .scaleEffect(configuration.isPressed ? 0.99: 1)
            .foregroundColor(.primary)
            .font(.system(.headline, design: .rounded))
            .onTapGesture(perform: simpleSuccess)
    }
}
