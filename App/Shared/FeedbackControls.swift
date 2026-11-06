import GoodskyCore
import SwiftUI

/// "Was this right?" 👍/👎. A 👎 asks what went wrong, then nudges the thresholds.
/// Used under the Jacket Call on both the iPhone and the Watch.
struct FeedbackControls: View {
    @Environment(WeatherModel.self) private var model
    let call: JacketCall
    @State private var askingWhy = false

    var body: some View {
        if let record = model.todaysFeedback {
            voted(record)
        } else {
            ask
        }
    }

    private var ask: some View {
        HStack(spacing: 12) {
            Text("Was this right?")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("👍") { model.submit(.right) }
                .accessibilityLabel("Yes, the call was right")
            Button("👎") { askingWhy = true }
                .accessibilityLabel("No, the call was wrong")
        }
        .buttonStyle(.bordered)
        .confirmationDialog("What went wrong?", isPresented: $askingWhy, titleVisibility: .visible) {
            ForEach(JacketFeedback.complaints(for: call), id: \.self) { complaint in
                Button(complaint.label) { model.submit(complaint) }
            }
            Button("Never mind", role: .cancel) {}
        }
    }

    private func voted(_ record: FeedbackRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.feedback == .right ? "👍 You said I nailed it." : "👎 \(record.feedback.label).")
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 0)
                Button("Undo") { model.undoTodaysFeedback() }
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
            if let tuning = model.lastTuning {
                Text(tuning.message)
                    .font(.footnote.italic())
                    .foregroundStyle(.secondary)
                ForEach(tuning.changes, id: \.self) { change in
                    Text(change).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
