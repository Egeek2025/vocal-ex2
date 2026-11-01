import SwiftUI

/// The day's practice from the current teacher's plan, in order, with the week's progress.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmAdvance = false

    var body: some View {
        let plan = model.todayPlan
        let info = Course.weeks[plan.week]
        let progress = Routine.progress(week: plan.week, summary: model.summary)
        let doneCount = plan.steps.filter { model.isDone($0) }.count
        let next = plan.steps.first { !model.isDone($0) }
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    TeacherPicker()
                    Text(model.teacher.about).font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text("第 \(plan.week + 1) 周").font(.title2.weight(.bold))
                        Text("阶段 \(info.stage) · \(Course.stageNames[info.stage] ?? "")")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Color.stage(info.stage).opacity(0.18)))
                            .foregroundStyle(Color.stage(info.stage))
                    }
                    Text(info.focus).font(.headline)
                    Text(plan.headline).font(.callout).foregroundStyle(.secondary)
                    ProgressView(value: Double(progress.done), total: Double(max(1, progress.total))) {
                        Text("本周练习已练 \(progress.done)/\(progress.total) 个").font(.caption)
                    }
                    if !plan.isRest {
                        Text("今天约 \(plan.minutes) 分钟 · 已完成 \(doneCount)/\(plan.steps.count) 步")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                if let next {
                    nextButton(next)
                } else if !plan.isRest {
                    Label("今天的练习都完成了，明天继续。", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }

            if plan.isRest {
                Section {
                    Text("按方案每周练 6 天，第 7 天休息，让嗓子恢复。想动一动的话，只做轻柔的唇颤音热身就好。")
                        .font(.callout)
                    if let first = Course.warmup.first, let trill = Course.byID[first] {
                        NavigationLink(value: RoutineStep(id: "rest.trill", kind: .warmup, exercise: trill.id, minutes: 3,
                                                          title: trill.name, detail: "轻柔地唱几个调。", maxKeys: 4)) {
                            Label("轻松热身（可选）", systemImage: "wind")
                        }
                    }
                }
            } else {
                Section("今天的流程") {
                    ForEach(Array(plan.steps.enumerated()), id: \.element.id) { i, step in
                        StepRow(index: i + 1, step: step, done: model.isDone(step))
                    }
                }
            }

            if model.teacher.hasPrograms {
            Section {
                ForEach(Routine.Program.allCases) { program in
                    let steps = Routine.steps(program)
                    NavigationLink(value: program) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(program.title) · 约 \(steps.reduce(0) { $0 + $1.minutes }) 分钟").font(.body.weight(.semibold))
                            Text(program.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("专项练习")
            } footer: {
                Text("不占用每天的课程进度，什么时候都可以单独做。")
            }
            }

            Section {
                CourseVideosButton()
            }

            Section {
                if plan.week + 1 < Course.weeks.count {
                    Button {
                        confirmAdvance = true
                    } label: {
                        Label("完成第 \(plan.week + 1) 周，进入第 \(plan.week + 2) 周", systemImage: "arrow.right.circle")
                    }
                } else {
                    Text("这是最后一周。做完结业检验后，可以把前面各周的检验项目当作长期练习。").font(.callout)
                }
                Picker("从某一周重新开始", selection: Binding(get: { model.courseWeek }, set: { model.startCourseWeek($0) })) {
                    ForEach(0..<Course.weeks.count, id: \.self) { w in
                        Text("第 \(w + 1) 周 · \(Course.weeks[w].focus)").tag(w)
                    }
                }
            } header: {
                Text("进度")
            } footer: {
                Text(advice(plan: plan, progress: progress))
            }
        }
        .navigationTitle("今日练习")
        .toolbar { ToolbarItem { SettingsButton() } }
        .navigationDestination(for: RoutineStep.self) { step in
            if let id = step.exercise, let ex = Course.byID[id] {
                ExerciseView(exercise: ex, voice: model.voice, step: step)
            }
        }
        .navigationDestination(for: Routine.Program.self) { program in
            ProgramView(program: program)
        }
        .confirmationDialog("进入第 \(plan.week + 2) 周？", isPresented: $confirmAdvance, titleVisibility: .visible) {
            Button("进入第 \(plan.week + 2) 周") { model.startCourseWeek(plan.week + 1) }
        } message: {
            Text(progress.done < progress.total ? "本周还有 \(progress.total - progress.done) 个练习没练过。进入下一周后，它们会出现在复习里。" : "今天会成为新一周的第 1 天。")
        }
    }

    @ViewBuilder
    private func nextButton(_ step: RoutineStep) -> some View {
        if step.exercise != nil {
            NavigationLink(value: step) {
                Label("下一步：\(step.kind.label) · \(step.title)", systemImage: "play.circle.fill").font(.headline)
            }
        } else {
            Button {
                model.markDone(step)
            } label: {
                Label("下一步：\(step.title)，完成后点这里", systemImage: "checkmark.circle").font(.headline)
            }
        }
    }

    private func advice(plan: DayPlan, progress: (done: Int, total: Int)) -> String {
        if plan.day > 7 {
            return "这一周已经超过 7 天。本周练习都练过、检验也做了，就可以进入下一周；跟不上时多留一周也完全没问题。"
        }
        if progress.done == progress.total && plan.day >= 6 {
            return "本周练习都练过了。做完本周检验后，就可以进入下一周。"
        }
        return "建议本周练习都至少练过一次、做完第 6 天的检验后，再进入下一周。"
    }
}

/// One of the fixed programs (quick warm-up, head voice), step by step.
struct ProgramView: View {
    @Environment(AppModel.self) private var model
    let program: Routine.Program

    var body: some View {
        let steps = Routine.steps(program)
        let next = steps.first { !model.isDone($0) }
        List {
            Section {
                Text(program.summary).font(.callout)
                if let next {
                    if next.exercise != nil {
                        NavigationLink(value: next) {
                            Label("下一步：\(next.title)", systemImage: "play.circle.fill").font(.headline)
                        }
                    } else {
                        Button { model.markDone(next) } label: {
                            Label("下一步：\(next.title)，完成后点这里", systemImage: "checkmark.circle").font(.headline)
                        }
                    }
                } else {
                    Label("今天已经做完了。", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
            Section("步骤") {
                ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                    StepRow(index: i + 1, step: step, done: model.isDone(step))
                }
            }
        }
        .navigationTitle(program.title)
    }
}

struct StepRow: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let step: RoutineStep
    let done: Bool

    var body: some View {
        if let id = step.exercise {
            HStack {
                NavigationLink(value: step) { content }
                if let ex = Course.byID[id] { VideoQuickButton(exercise: ex) }
            }
        } else {
            HStack {
                content
                Button(done ? "已完成" : "完成") { if !done { model.markDone(step) } }
                    .buttonStyle(.bordered)
                    .disabled(done)
            }
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.secondary.opacity(0.15)).frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(index)").font(.caption.weight(.semibold).monospacedDigit())
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(step.kind.label).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    Text(step.title).font(.body.weight(.semibold))
                }
                Text(step.detail).font(.caption).foregroundStyle(.secondary)
                Text("约 \(step.minutes) 分钟" + (step.maxKeys.map { " · 唱 \($0) 个调" } ?? "") + (step.watchFirst ? " · 先看视频" : ""))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .opacity(done ? 0.6 : 1)
        }
        .padding(.vertical, 2)
    }
}

/// Shown on an exercise opened from the daily routine.
struct RoutineBanner: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let step: RoutineStep
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日练习 · \(step.kind.label)").font(.caption.weight(.semibold)).foregroundStyle(.tint)
            Text(step.detail).font(.callout)
            if step.watchFirst {
                CourseVideoButton(exercise: exercise,
                                  title: "先看视频：Ep. \(exercise.ep)" + (exercise.t > 0 ? "，从 \(Course.mmss(exercise.t)) 开始" : ""))
            }
            if let k = step.maxKeys {
                Text("这一步只唱 \(k) 个调。").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if model.isDone(step) {
                    Label("这一步已完成", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Spacer()
                Button("返回今日练习") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .font(.callout)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
    }
}
