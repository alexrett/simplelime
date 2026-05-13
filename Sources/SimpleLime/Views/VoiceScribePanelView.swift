import SwiftUI

struct VoiceScribePanelView: View {
    @ObservedObject var store: EditorStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    transcriptFields
                    automationControls
                    controls
                    statusBlock
                    partialBlock
                }
                .padding(14)
            }
        }
        .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: store.isVoiceScribeRunning ? "waveform.circle.fill" : "waveform.circle")
                .foregroundStyle(store.isVoiceScribeRunning ? Color.accentColor : Color.secondary)
            Text("Scribe")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                store.toggleVoiceScribe()
            } label: {
                Image(systemName: store.isVoiceScribeRunning ? "stop.fill" : "mic.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(store.isVoiceScribeRunning ? "Stop voice scribe" : "Start voice scribe")

            Button {
                store.hideScribePanel()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Hide scribe")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var transcriptFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledField("Transcript", text: $store.voiceScribeTitle)
            labeledField("Speaker", text: $store.voiceScribeSpeaker)
            sourcePicker
            Toggle("Voice commands", isOn: $store.isVoiceScribeCommandCaptureEnabled)
                .toggleStyle(.switch)
                .font(.system(size: 12))
                .disabled(store.isVoiceScribeRunning)
                .help("Route wake-phrase commands through the local command handler")
        }
        .disabled(store.isVoiceScribeRunning)
    }

    private var automationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Auto-start meetings", isOn: $store.isVoiceScribeAutoMeetingEnabled)
                .toggleStyle(.switch)
                .font(.system(size: 12))

            if let status = store.voiceScribeAutoMeetingStatus {
                Label(status, systemImage: store.isVoiceScribeAutoMeetingEnabled ? "video.badge.waveform" : "video.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Source", selection: $store.voiceScribeAudioSource) {
                ForEach(VoiceScribeAudioSource.allCases) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            if store.voiceScribeAudioSource == .autoMeeting {
                Label(
                    store.voiceScribeDetectedMeetingApp.map { "Detected \($0.displayName)" } ?? "Auto meeting detection",
                    systemImage: store.voiceScribeDetectedMeetingApp == nil ? "video.badge.ellipsis" : "video.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack {
            Button {
                store.toggleVoiceScribe()
            } label: {
                Label(store.isVoiceScribeRunning ? "Stop" : "Start", systemImage: store.isVoiceScribeRunning ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Status", systemImage: "dot.radiowaves.left.and.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(store.voiceScribeStatus ?? "Idle")
                .font(.system(size: 12))
                .foregroundStyle(store.isVoiceScribeRunning ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private var partialBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Live Text", systemImage: "text.bubble")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(store.voiceScribePartialTranscript.isEmpty ? " " : store.voiceScribePartialTranscript)
                .font(.system(size: 12))
                .foregroundStyle(store.voiceScribePartialTranscript.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                .padding(9)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }
}
