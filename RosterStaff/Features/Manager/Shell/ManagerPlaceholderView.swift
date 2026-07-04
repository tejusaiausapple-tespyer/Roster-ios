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
                HStack(spacing: 6) {
                    Image(systemName: tab.icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(hex: 0x4F46E5))
                    Text(tab.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(UIColor.label))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(hex: 0x4F46E5).opacity(0.12)))
            }
        }
    }
}

#Preview {
    NavigationStack {
        ManagerPlaceholderView(tab: .dashboard)
    }
}