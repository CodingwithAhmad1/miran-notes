import SwiftUI

struct PlanningMenuBarView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        if let planning = appModel.planningModel {
            PlanningRootView(model: planning)
                .frame(minWidth: 640, minHeight: 520)
        } else {
            ProgressView("Initializing Planning…")
                .frame(width: 300, height: 160)
        }
    }
}
