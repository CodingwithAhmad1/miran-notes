import SwiftUI

/// Landing page when the vault tray is selected (full vault with folders). Body intentionally empty for now.
struct TodaysTasksVaultPageView: View {
    var body: some View {
        Text("Today’s Tasks")
            .font(.largeTitle)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
    }
}
