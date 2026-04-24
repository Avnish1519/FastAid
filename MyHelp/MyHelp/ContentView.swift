//
//  ContentView.swift
//  MyHelp
//
//  Created by Avnish Singh on 24/01/26.
//
import SwiftUI
import AVFoundation
import Speech

// MARK: - 1. THE DATA ENGINE (Logic)
@Observable
class GuardianEngine: NSObject {
    var currentState: EmergencyMode = .inquiring
    var transcript: String = "" { didSet { checkSpeechForKeywords() } }
    var isListening: Bool = false
    var feedbackMsg: String = "Initializing..."
    var statusColor: Color = .blue
    
    private var lastProcessedCommand: String = ""
    private let synthesizer = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    enum EmergencyMode { case inquiring, burn, bleeding }

    func welcomeUser() {
        let welcome = "Hello. How may I help you?"
        feedbackMsg = welcome
        speak(welcome)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { try? self.startListening() }
    }

    private func checkSpeechForKeywords() {
        let input = transcript.lowercased().trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty, input != lastProcessedCommand else { return }

        if currentState == .inquiring {
            if input.contains("burn") { selectEmergency(.burn) }
            else if input.contains("bleed") { selectEmergency(.bleeding) }
        } else {
            for item in itemsForCurrentMode() {
                if input.contains(item.name.lowercased()) {
                    handleSelection(item)
                    break
                }
            }
        }
    }

    func selectEmergency(_ mode: EmergencyMode) {
        stopListening()
        currentState = mode
        lastProcessedCommand = transcript
        let msg = mode == .burn ? "Burn protocol. What do you have?" : "Bleeding protocol. What items are available?"
        feedbackMsg = msg
        statusColor = mode == .burn ? .orange : .red
        speak(msg)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.transcript = ""; try? self.startListening() }
    }

    func handleSelection(_ item: InventoryItem) {
        feedbackMsg = item.feedback
        statusColor = item.isSafe ? .green : .red
        speak(item.feedback)
        stopListening()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.transcript = ""; try? self.startListening() }
    }

    func toggleListening() { isListening ? stopListening() : (try? startListening()) }

    private func startListening() throws {
        if isListening { return }
        recognitionTask?.cancel()
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true)
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { result, _ in
            if let result = result { self.transcript = result.bestTranscription.formattedString }
        }
        let node = audioEngine.inputNode
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { (b, _) in self.recognitionRequest?.append(b) }
        try audioEngine.start()
        isListening = true
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isListening = false
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.45
        synthesizer.speak(utterance)
    }
    
    func itemsForCurrentMode() -> [InventoryItem] {
        currentState == .burn ? [
            InventoryItem(name: "Ice", icon: "snowflake", isSafe: false, feedback: "No! Ice damages skin. Use water."),
            InventoryItem(name: "Water", icon: "drop.fill", isSafe: true, feedback: "Yes. Use cool tap water."),
            InventoryItem(name: "Butter", icon: "square.fill", isSafe: false, feedback: "No. Butter traps heat."),
            InventoryItem(name: "Wrap", icon: "doc.on.doc", isSafe: true, feedback: "Yes. Wrap the wound loosely.")
        ] : [
            InventoryItem(name: "Cloth", icon: "square.dashed", isSafe: true, feedback: "Good. Apply firm pressure."),
            InventoryItem(name: "Alcohol", icon: "ivfluid.bag", isSafe: false, feedback: "No alcohol in the wound.")
        ]
    }
    
    func reset() { stopListening(); currentState = .inquiring; statusColor = .blue; welcomeUser() }
}

// MARK: - 2. THE IMPROVED UI
struct InventoryItem: Identifiable {
    let id = UUID(); let name: String; let icon: String; let isSafe: Bool; let feedback: String
}

struct ContentView: View {
    @State private var engine = GuardianEngine()
    @State private var isBreathing = false
    
    var body: some View {
        ZStack {
            // Adaptive Background
            engine.statusColor.opacity(0.1).ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                headerView

                // Main Instruction Card with Breathing Anchor
                ZStack {
                    // Breathing Circle Animation
                    Circle()
                        .stroke(engine.statusColor.opacity(0.3), lineWidth: 20)
                        .scaleEffect(isBreathing ? 1.1 : 0.9)
                        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: isBreathing)
                    
                    Text(engine.feedbackMsg)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .padding(40)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .shadow(color: engine.statusColor.opacity(0.1), radius: 20)
                .padding(.horizontal)

                if engine.currentState == .inquiring {
                    homeTriageList
                } else {
                    inventoryGrid
                }

                Spacer()
                
                bottomControlPanel
            }
        }
        .onAppear {
            engine.welcomeUser()
            isBreathing = true
        }
        .animation(.spring(), value: engine.currentState)
    }
    
    // MARK: - UI Sub-Views
    private var headerView: some View {
        HStack {
            Text("GUARDIAN")
                .font(.system(.caption, design: .rounded)).bold().tracking(5)
                .foregroundColor(engine.statusColor)
            Spacer()
            if engine.currentState != .inquiring {
                Button("RESET") { engine.reset() }
                    .font(.caption2.bold())
                    .padding(10).background(.white.opacity(0.5)).cornerRadius(10)
            }
        }
        .padding(.horizontal, 25)
    }

    private var homeTriageList: some View {
        VStack(spacing: 16) {
            TriageCard(title: "Severe Burn", subtitle: "Fire, heat, or chemicals", icon: "flame.fill", color: .orange) {
                engine.selectEmergency(.burn)
            }
            TriageCard(title: "Bleeding", subtitle: "Deep cuts or wounds", icon: "drop.fill", color: .red) {
                engine.selectEmergency(.bleeding)
            }
        }
        .padding(.horizontal)
    }

    private var inventoryGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(engine.itemsForCurrentMode()) { item in
                    InventoryCard(item: item) { engine.handleSelection(item) }
                }
            }
            .padding()
            
            
        }
    }

    private var bottomControlPanel: some View {
        VStack(spacing: 15) {
            if !engine.transcript.isEmpty {
                Text(engine.transcript)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 20)
                    .padding(8).background(.black.opacity(0.05)).cornerRadius(8)
            }
            
            Button(action: { engine.toggleListening() }) {
                ZStack {
                    Circle()
                        .fill(engine.isListening ? .red : engine.statusColor)
                        .frame(width: 75, height: 75)
                        .shadow(color: (engine.isListening ? .red : engine.statusColor).opacity(0.3), radius: 15)
                    
                    Image(systemName: engine.isListening ? "stop.fill" : "mic.fill")
                        .font(.title2).foregroundColor(.white)
                }
            }
            .symbolEffect(.pulse, isActive: engine.isListening)
            
            Text(engine.isListening ? "I'M LISTENING..." : "TAP TO SPEAK")
                .font(.system(.caption2, design: .rounded)).bold()
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - UI COMPONENTS
struct TriageCard: View {
    let title: String; let subtitle: String; let icon: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon).font(.title2).foregroundColor(.white)
                    .frame(width: 50, height: 50).background(color).cornerRadius(12)
                VStack(alignment: .leading) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .padding().background(Color.white).cornerRadius(20)
            .shadow(color: .black.opacity(0.03), radius: 10)
        }
        .buttonStyle(.plain)
    }
}

struct InventoryCard: View {
    let item: InventoryItem; let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: item.icon).font(.system(size: 30)).foregroundColor(.primary)
                Text(item.name).font(.callout.bold())
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(Color.white)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.03), radius: 10)
        }
        .buttonStyle(.plain)
    }
}
#Preview{
    ContentView()
}
