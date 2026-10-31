import SwiftUI

@main
struct VocalStudioApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(VideoLibrary.shared)
                .tint(.indigo)
        }
        .onChange(of: phase) { _, p in
            // let go of the microphone and the audio hardware as soon as the app is out of sight
            if p == .background { AudioEngine.shared.stopIfIdle(force: true) }
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            NavigationStack { TodayView() }
                .tabItem { Label("今日练习", systemImage: "checklist") }
                .tag(AppTab.today)
            PracticeRoot()
                .tabItem { Label("课程", systemImage: "music.mic") }
                .tag(AppTab.practice)
            NavigationStack { RangeView() }
                .tabItem { Label("音域", systemImage: "arrow.up.and.down") }
                .tag(AppTab.range)
            NavigationStack { AnalyzeView() }
                .tabItem { Label("录音分析", systemImage: "waveform") }
                .tag(AppTab.analyze)
            NavigationStack { LogView() }
                .tabItem { Label("记录", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.log)
        }
    }
}
