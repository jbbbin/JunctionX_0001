import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var state: AppViewModel
    @State private var pendingDeletion: ApplicationWorkspace?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 20)
            
            applicationSectionHeader
            
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(state.workspaces) { workspace in
                        applicationCard(workspace)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 202)
            
            Divider()
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            
            VStack(spacing: 4) {
                navigationButton(.overview)
                supportDocumentsButton
                auditButton
            }
            .padding(.horizontal, 10)
            
            Spacer(minLength: 16)

            Divider()
                .padding(.horizontal, 18)

            profileFooter
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            "지원 항목을 삭제할까요?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { workspace in
            Button("취소", role: .cancel) { pendingDeletion = nil }
            Button("삭제", role: .destructive) {
                state.deleteWorkspace(workspace.id)
                pendingDeletion = nil
            }
        } message: { workspace in
            Text("\(workspace.school) · \(workspace.program)의 모집요강, 서류 목록과 검수 이력이 이 Mac에서 삭제됩니다.")
        }
    }
    
    private var applicationSectionHeader: some View {
        HStack(spacing: 8) {
            Text("APPLICATION")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.15)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                state.showNewWorkspace = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(GCTheme.brand)
            .help("새 지원 목표")
            .accessibilityLabel("새 지원 목표")
        }
        .padding(.leading, 19)
        .padding(.trailing, 15)
        .padding(.bottom, 8)
    }
    
    private var supportDocumentsButton: some View {
        let isSelected = state.destination == .documents || state.destination == .requirements
        
        return Button {
            state.showSelectedWorkspaceDocuments()
        } label: {
            navigationLabel(for: .documents, isSelected: isSelected)
                .gcSidebarTab(selected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    private func navigationButton(_ destination: AppDestination) -> some View {
        let isSelected = state.destination == destination
        
        return Button {
            state.destination = destination
        } label: {
            navigationLabel(for: destination, isSelected: isSelected)
                .gcSidebarTab(selected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    private var auditButton: some View {
        let isSelected = state.destination == .audit
        
        return Button {
            state.showSelectedWorkspaceAudit()
        } label: {
            navigationLabel(for: .audit, isSelected: isSelected)
                .gcSidebarTab(selected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    private func applicationCard(_ workspace: ApplicationWorkspace) -> some View {
        let isSelected = workspace.id == state.selectedWorkspaceID
        
        return ZStack(alignment: .topTrailing) {
            Button {
                state.selectWorkspaceFromSidebar(workspace.id)
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? GCTheme.brand.opacity(0.16) : GCTheme.secondaryInk.opacity(0.07))
                            Text(workspace.school.prefix(1))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(isSelected ? GCTheme.brand : GCTheme.secondaryInk)
                        }
                        .frame(width: 31, height: 31)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspace.school)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(GCTheme.ink)
                                .lineLimit(1)
                            Text(workspace.program)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 24)
                    }
                    HStack {
                        Circle()
                            .fill(workspace.status.color)
                            .frame(width: 6, height: 6)
                        Text(workspace.status.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(workspace.status.color)
                        Spacer()
                        Text(workspace.intake)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(11)
                .padding(.leading, 3)
                .background(
                    isSelected ? GCTheme.brand.opacity(0.10) : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(GCTheme.brand)
                        .frame(width: 3)
                        .padding(.vertical, 12)
                        .opacity(isSelected ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            
            Menu {
                Button(role: .destructive) {
                    pendingDeletion = workspace
                } label: {
                    Label("지원 항목 삭제", systemImage: "trash")
                }
                .disabled(state.workspaces.count <= 1)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .padding(.top, 8)
            .padding(.trailing, 6)
            .help(state.workspaces.count <= 1 ? "마지막 지원 항목은 삭제할 수 없습니다." : "지원 항목 관리")
        }
    }
    
    private func navigationLabel(for destination: AppDestination, isSelected: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: destination.symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 20)
            Text(destination.rawValue)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            Spacer()
            if destination == .audit && state.blockedCount > 0 {
                Text("\(state.blockedCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 19, minHeight: 19)
                    .background(ReviewStatus.blocked.color)
                    .clipShape(Circle())
            }
        }
        .foregroundStyle(isSelected ? GCTheme.brand : GCTheme.secondaryInk)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    private var brand: some View {
        HStack(spacing: 10) {
            Image(nsImage: UpCheckIconAsset.logo)
                .resizable()
                .scaledToFit()
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("UpCheck")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(GCTheme.ink)
            }
        }
    }

    private var profileFooter: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(ApplicantProfile.current.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GCTheme.secondaryInk)
                Text(ApplicantProfile.current.email)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private enum UpCheckIconAsset {
    static let logo: NSImage = {
        guard let url = Bundle.main.url(forResource: "UpCheckLogo", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: nil) ?? NSImage()
        }
        return image
    }()
}
