import SwiftUI

struct Note: Identifiable, Hashable {
    var id: Int          // 新建还没存的是 0
    var rev: Int
    var text: String
    var pinned: Bool
    var updated: String
    var updatedRaw: String
    var deleted: String

    init(_ d: [String: Any]) {
        id = d.int("id"); rev = d.int("rev"); text = d.str("text"); pinned = d.bool("pinned")
        updated = d.str("updated"); updatedRaw = d.str("updatedRaw"); deleted = d.str("deleted")
    }
    init() { id = 0; rev = 0; text = ""; pinned = false; updated = ""; updatedRaw = ""; deleted = "" }

    var title: String {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }.map { String($0.prefix(80)) } ?? "新备忘录"
    }
    var preview: String {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.count > 1 ? String(lines[1].prefix(80)) : "没有其他内容"
    }
}

@MainActor
final class NotesStore: ObservableObject {
    var api: API!
    @Published var notes: [Note] = []
    @Published var trashCount = 0
    @Published var error: String?
    @Published var loaded = false

    func load() async {
        do {
            let d = try await api.get("/admin/vault/api/notes")
            notes = d.list("entries").map(Note.init)
            trashCount = d.int("trashCount")
            error = nil
        } catch { self.error = error.localizedDescription }
        loaded = true
    }

    var sorted: [Note] {
        notes.sorted { a, b in a.pinned != b.pinned ? a.pinned : (a.updatedRaw, a.id) > (b.updatedRaw, b.id) }
    }

    /// 保存；版本对不上时抛 409（别的设备刚改过）
    func save(_ n: Note, force: Bool = false) async throws -> Note {
        let data: [String: Any] = ["text": n.text, "pinned": n.pinned]
        let d = n.id == 0 ? try await api.post("/admin/vault/api/notes", ["data": data])
                          : try await api.put("/admin/vault/api/notes/\(n.id)", ["rev": n.rev, "data": data, "force": force])
        let saved = Note(d.dict("entry"))
        if let i = notes.firstIndex(where: { $0.id == saved.id }) { notes[i] = saved } else { notes.append(saved) }
        return saved
    }

    func remove(_ n: Note) async throws {
        _ = try await api.delete("/admin/vault/api/notes/\(n.id)")
        notes.removeAll { $0.id == n.id }; trashCount += 1
    }
    func trash() async throws -> [Note] { try await api.get("/admin/vault/api/notes?trash=1").list("entries").map(Note.init) }
    func restore(_ n: Note) async throws {
        let d = try await api.post("/admin/vault/api/notes/\(n.id)/restore")
        notes.append(Note(d.dict("entry"))); trashCount = max(0, trashCount - 1)
    }
    func purge(_ n: Note) async throws {
        _ = try await api.delete("/admin/vault/api/notes/\(n.id)?purge=1"); trashCount = max(0, trashCount - 1)
    }
}

struct NotesView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var toast: Toast
    @State private var query = ""
    @State private var path: [NoteRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                let list = filtered
                let pinned = list.filter(\.pinned), rest = list.filter { !$0.pinned }
                if !pinned.isEmpty { Section("置顶") { ForEach(pinned) { row($0) } } }
                if !rest.isEmpty { Section(pinned.isEmpty ? "" : "备忘录") { ForEach(rest) { row($0) } } }
                if store.loaded && store.notes.isEmpty && store.error == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "note.text").font(.largeTitle).foregroundStyle(.secondary)
                        Text("还没有备忘录").font(.headline)
                        Text("点右上角新建，第一行会作为标题，边写边自动保存。").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 30)
                }
                if store.trashCount > 0 {
                    Section { NavigationLink { NotesTrashView() } label: { Label("最近删除  \(store.trashCount)", systemImage: "trash") } }
                }
                if let e = store.error { ErrorBanner(message: e) { Task { await store.load() } } }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("备忘录")
            .searchable(text: $query, prompt: "搜索")
            .refreshable { await store.load() }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button { path.append(.new) } label: { Image(systemName: "square.and.pencil") } } }
            .navigationDestination(for: NoteRoute.self) { r in
                switch r {
                case .new: NoteEditor(initial: Note())
                case .note(let id): NoteEditor(initial: store.notes.first { $0.id == id } ?? Note())
                }
            }
            .task { store.api = api; if !store.loaded { await store.load() } }
        }
    }

    private var filtered: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.sorted.filter { q.isEmpty || $0.text.lowercased().contains(q) }
    }

    private func row(_ n: Note) -> some View {
        NavigationLink(value: NoteRoute.note(n.id)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(n.title).font(.body.weight(.semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    Text(shortDate(n.updated)).foregroundStyle(.secondary)
                    Text(n.preview).foregroundStyle(.tertiary).lineLimit(1)
                }.font(.subheadline)
            }.padding(.vertical, 2)
        }
        .swipeActions(edge: .leading) {
            Button { Task { var m = n; m.pinned.toggle(); _ = try? await store.save(m, force: true) } } label: {
                Label(n.pinned ? "取消置顶" : "置顶", systemImage: n.pinned ? "pin.slash" : "pin")
            }.tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { Task { do { try await store.remove(n); toast.show("已移到「最近删除」") } catch { toast.show(error.localizedDescription) } } } label: { Label("删除", systemImage: "trash") }
        }
    }
}

enum NoteRoute: Hashable { case new, note(Int) }

func shortDate(_ s: String) -> String {
    guard s.count >= 16 else { return s }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "Asia/Shanghai")
    let today = f.string(from: Date())
    if s.hasPrefix(today) { return String(s.dropFirst(11).prefix(5)) }
    if s.prefix(4) == today.prefix(4) { return String(s.dropFirst(5).prefix(5)) }
    return String(s.prefix(10))
}

/// 编辑一条备忘录：停顿 0.7 秒自动保存；离开页面、切到后台时立刻保存。
struct NoteEditor: View {
    let initial: Note
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var toast: Toast
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var note = Note()
    @State private var status = ""
    @State private var dirty = false
    @State private var saving = false
    @State private var timer: Task<Void, Never>?
    @State private var conflict: Note?
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $note.text)
            .font(.system(size: 17))
            .lineSpacing(4)
            .padding(.horizontal, 12)
            .focused($focused)
            .onChange(of: note.text) { _ in changed() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(note.id == 0 && note.text.isEmpty ? "新备忘录" : note.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        if !status.isEmpty { Text(status).font(.caption2).foregroundStyle(status.contains("失败") ? Color.bad : .secondary) }
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button { note.pinned.toggle(); changed(now: true) } label: { Label(note.pinned ? "取消置顶" : "置顶", systemImage: "pin") }
                        Button { toast.copy(note.text, "已复制全文") } label: { Label("复制全文", systemImage: "doc.on.doc") }
                        ShareLink(item: note.text) { Label("分享…", systemImage: "square.and.arrow.up") }
                        if note.id != 0 {
                            Divider()
                            Button(role: .destructive) { Task { timer?.cancel(); dirty = false; try? await store.remove(note); toast.show("已移到「最近删除」"); dismiss() } } label: { Label("删除", systemImage: "trash") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    if focused { Button("完成") { focused = false; Task { await flush() } } }
                }
            }
            .onAppear { note = initial; if initial.id == 0 { focused = true } }
            .onDisappear { Task { await flush() } }
            .onChange(of: phase) { if $0 != .active { Task { await flush() } } }
            .alert("这条备忘录在别处改过了", isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } })) {
                Button("用那边的版本") { if let r = conflict { note = r; dirty = false; status = "已载入最新" } }
                Button("保留我现在的", role: .destructive) { Task { await save(force: true) } }
            } message: { Text("别的设备上刚修改过（\(conflict?.updated ?? "")）。要保留哪一个版本？") }
    }

    private func changed(now: Bool = false) {
        dirty = true; status = "有改动…"
        timer?.cancel()
        timer = Task { if !now { try? await Task.sleep(nanoseconds: 700_000_000) }; if !Task.isCancelled { await save() } }
    }

    private func flush() async { if dirty { timer?.cancel(); await save() } }

    private func save(force: Bool = false) async {
        guard dirty || force else { return }
        if note.id == 0 && note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { dirty = false; status = ""; return }
        if saving { try? await Task.sleep(nanoseconds: 300_000_000); return await save(force: force) }
        saving = true; dirty = false; status = "保存中…"
        do {
            let s = try await store.save(note, force: force)
            note.id = s.id; note.rev = s.rev; note.updated = s.updated; note.updatedRaw = s.updatedRaw
            status = dirty ? "有改动…" : "已保存"
        } catch let e as APIError where e.code == 409 {
            conflict = Note(e.payload.dict("entry")); dirty = true; status = ""
        } catch {
            dirty = true; status = "保存失败，稍后自动重试"
            timer = Task { try? await Task.sleep(nanoseconds: 5_000_000_000); if !Task.isCancelled { await save() } }
        }
        saving = false
    }
}

struct NotesTrashView: View {
    @EnvironmentObject var store: NotesStore
    @EnvironmentObject var toast: Toast
    @State private var list: [Note] = []
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                ForEach(list) { n in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.title).font(.body.weight(.medium))
                        Text("删除于 \(n.deleted)").font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .leading) {
                        Button { act { try await store.restore(n); toast.show("已恢复") } } label: { Label("恢复", systemImage: "arrow.uturn.backward") }.tint(.good)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { act { try await store.purge(n); toast.show("已彻底删除") } } label: { Label("彻底删除", systemImage: "trash") }
                    }
                }
            } footer: { Text(list.isEmpty && loaded ? "「最近删除」是空的。" : "右滑恢复，左滑彻底删除。删除的备忘录保留 30 天。") }
        }
        .navigationTitle("最近删除")
        .task { list = (try? await store.trash()) ?? []; loaded = true }
    }

    private func act(_ f: @escaping () async throws -> Void) {
        Task { do { try await f(); list = (try? await store.trash()) ?? [] } catch { toast.show(error.localizedDescription) } }
    }
}
