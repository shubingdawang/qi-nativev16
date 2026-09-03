import SwiftUI

/// 又补的那三套的界面：梅花易数、数字命理、择日。
///
/// 算法在 `DivinationPro.swift`，那儿也写了**为什么只补这三套**
/// （标准还是那条：盘面得是真的）。
///
/// ⚠️ 这三个面板全部复用 `QuestionBox` / `ReadingBox`——
/// 「让他解」那一步是要花钱的，那句提示只在 `ReadingBox` 里有一份，
/// 自己再写一遍的话，哪天改了措辞就会有一处还留着老的。

// MARK: - 梅花易数

struct MeihuaPane: View {

    @Binding var question: String
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DivinationStore.shared

    @State private var record: DivinationRecord?
    @State private var reading = ""
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuestionBox(question: $question, hint: "想问什么")

            Text("不摇钱不抽牌——**按你按下去的那一刻起卦**。所以想清楚了再按。")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let rec = record {
                Text(rec.layout)
                    .font(.app(13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.textMain(scheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.softFillDeep))
            }

            Button { cast() } label: {
                Text(record == nil ? "起卦" : "再起一卦")
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(app.settings.accentColor.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)

            if let rec = record {
                ReadingBox(record: rec, reading: $reading, asking: $asking)
            }
        }
        .glassCard()
    }

    private func cast() {
        let r = DivinePro.meihua()
        var rec = DivinationRecord(kind: "meihua", question: question, layout: r.layout)
        // 本卦变卦也存进去。⚠️ 存了它，历史里那一条才画得出卦象；
        // 只存 layout 的话，那条记录就只是一段文字。
        rec.primary = r.primary
        rec.changed = r.changed
        record = rec
        reading = ""
        store.add(rec)
        if app.settings.haptics {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - 数字命理

struct NumerologyPane: View {

    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DivinationStore.shared

    /// ⚠️ 默认给 1995 年，不给今天。
    /// 给今天的话她一打开就是「今年出生」，还得从 2026 一路滚回去。
    @State private var birth = Calendar.current.date(
        from: DateComponents(year: 1995, month: 1, day: 1)) ?? Date()
    @State private var record: DivinationRecord?
    @State private var reading = ""
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("生日", selection: $birth, displayedComponents: .date)
                .font(.app(14))
                .datePickerStyle(.compact)

            Text("只用到年月日，**不需要时辰**——这一套跟八字不是一回事。")
                .font(.app(11))
                .foregroundStyle(Theme.textMuted(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let rec = record {
                Text(MD.inline(rec.layout))
                    .font(.app(13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.textMain(scheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.softFillDeep))
            }

            Button { run() } label: {
                Text(record == nil ? "算" : "再算一次")
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(app.settings.accentColor.opacity(0.3)))
            }
            .buttonStyle(.plain)

            if let rec = record {
                ReadingBox(record: rec, reading: $reading, asking: $asking)
            }
        }
        .glassCard()
    }

    private func run() {
        let layout = DivinePro.numerology(for: birth)
        let rec = DivinationRecord(kind: "numerology",
                                   question: "算这个生日", layout: layout)
        record = rec
        reading = ""
        store.add(rec)
        if app.settings.haptics {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - 择日

struct AlmanacPane: View {

    @Binding var question: String
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = DivinationStore.shared

    @State private var day = Date()
    @State private var record: DivinationRecord?
    @State private var reading = ""
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("看哪天", selection: $day, displayedComponents: .date)
                .font(.app(14))
                .datePickerStyle(.compact)

            QuestionBox(question: $question, hint: "想在这天做什么（可以不填）")

            if let rec = record {
                Text(MD.inline(rec.layout))
                    .font(.app(13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.textMain(scheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Theme.softFillDeep))
            }

            Button { look() } label: {
                Text(record == nil ? "看这天" : "再看一次")
                    .font(.app(15, weight: .medium))
                    .foregroundStyle(Theme.textMain(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14)
                        .fill(app.settings.accentColor.opacity(0.3)))
            }
            .buttonStyle(.plain)

            if let rec = record {
                ReadingBox(record: rec, reading: $reading, asking: $asking)
            }
        }
        .glassCard()
    }

    private func look() {
        let layout = DivinePro.almanac(for: day)
        let q = question.trimmingCharacters(in: .whitespaces)
        let rec = DivinationRecord(kind: "almanac",
                                   question: q.isEmpty ? "看看这天" : q,
                                   layout: layout)
        record = rec
        reading = ""
        store.add(rec)
        if app.settings.haptics {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
