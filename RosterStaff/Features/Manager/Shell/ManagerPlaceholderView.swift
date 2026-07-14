import SwiftUI

struct ManagerPlaceholderView: View {
    let tab: ManagerTab
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: tab.icon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color(hex: 0x4F46E5))
                    .padding(.bottom, 8)
                
                Text("Building \(tab.title) Tab")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color(UIColor.label))
                
                Text("This manager portal view is currently under construction. Stay tuned!")
                    .font(.subheadline)
                    .foregroundStyle(Color(UIColor.secondaryLabel))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding()
        }
        .navigationTitle(tab.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: tab.title, icon: tab.icon)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ManagerPlaceholderView(tab: .dashboard)
    }
}