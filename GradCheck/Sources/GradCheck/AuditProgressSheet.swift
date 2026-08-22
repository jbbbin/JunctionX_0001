import SwiftUI

struct AuditProgressSheet: View {
    @EnvironmentObject private var state: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(GCTheme.brandSoft)
                    Image(systemName: "checkmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(GCTheme.brand)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("지원 패키지를 검수하고 있어요")
                        .font(.system(size: 18, weight: .bold))
                    Text("문서에 적힌 사실만 사용해 근거를 연결합니다.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 24)

            VStack(spacing: 0) {
                ForEach(AuditPhase.allCases) { phase in
                    phaseRow(phase)
                    if phase != AuditPhase.allCases.last {
                        Rectangle()
                            .fill(phase.rawValue < state.auditPhase.rawValue ? GCTheme.brandBright : GCTheme.line)
                            .frame(width: 1, height: 18)
                            .padding(.leading, 15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Text("UpCheck는 합격 가능성을 평가하거나 원서를 대신 작성하지 않습니다.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 22)
        }
        .padding(28)
        .frame(width: 460)
        .background(GCTheme.canvas)
    }

    private func phaseRow(_ phase: AuditPhase) -> some View {
        let complete = phase.rawValue < state.auditPhase.rawValue
        let active = phase == state.auditPhase
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(complete || active ? GCTheme.brand : Color.black.opacity(0.055))
                if complete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else if active {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: phase.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 31, height: 31)
            Text(phase.title)
                .font(.system(size: 13, weight: active ? .semibold : .medium))
                .foregroundStyle(active || complete ? GCTheme.ink : .secondary)
            Spacer()
            if active {
                Text("진행 중")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GCTheme.brand)
            }
        }
    }
}
