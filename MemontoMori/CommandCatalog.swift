import Foundation

/// コマンドパレットから実行できる操作の識別子。
///
/// 実際の処理は `CommandPalette.run(_:)` が行い、ここには **何ができるか** だけを置く。
/// 設定ページのコマンド一覧もこの定義をそのまま読むので、追加はここ 1 か所で済む。
enum CommandID: String, CaseIterable, Identifiable {
    case searchFiles
    case showCommands
    case newMemo
    case newFolder
    case renameMemo
    case renameFolder
    case deleteMemo
    case deleteFolder
    case revealMemo
    case revealFolder
    case rescan
    case nextMemo
    case previousMemo
    case toggleRotationTarget
    case toggleRotation
    case togglePreview
    case toggleSidebar
    case togglePin
    case openSettings

    var id: String { rawValue }
}

/// 一覧を並べるときのまとまり。設定ページの見出しにもそのまま使う。
enum CommandCategory: String, CaseIterable, Identifiable {
    case search
    case file
    case folder
    case rotation
    case view

    var id: String { rawValue }

    var label: String {
        switch self {
        case .search: return "検索"
        case .file: return "ファイル"
        case .folder: return "フォルダ"
        case .rotation: return "ローテーション"
        case .view: return "表示"
        }
    }
}

/// パレットのキー操作の説明。パレット下部のヒント行と設定ページで共用する。
struct KeyHint: Identifiable, Equatable {
    let keys: String
    let description: String

    var id: String { keys }
}

struct CommandDescriptor: Identifiable, Equatable {
    let id: CommandID
    let category: CommandCategory
    let title: String
    /// 一覧に出す 1 行説明。
    let summary: String
    /// 曖昧検索でも引っかかるようにする別名（英語表記など）。
    let keywords: [String]
    /// メニューに割り当ててあるキー。無いものは `nil`。
    let shortcut: String?
    let systemImage: String

    /// 曖昧検索の対象。先頭がタイトルなので、タイトルに当たったときだけハイライトできる。
    var searchTargets: [String] { [title] + keywords }
}

extension CommandID {
    /// `switch` で網羅させることで、コマンドを足したときに定義漏れをコンパイラに検出させる。
    var descriptor: CommandDescriptor {
        switch self {
        case .searchFiles:
            return CommandDescriptor(
                id: self,
                category: .search,
                title: "ファイル・フォルダを検索",
                summary: "ルート配下のメモとフォルダを絞り込んで開きます。",
                keywords: ["search files", "find", "open file", "goto", "kensaku"],
                shortcut: "⌘P",
                systemImage: "magnifyingglass"
            )
        case .showCommands:
            return CommandDescriptor(
                id: self,
                category: .search,
                title: "コマンドを実行",
                summary: "コマンド一覧を絞り込んで実行します（入力欄の先頭が > のとき）。",
                keywords: ["command palette", "run command", "commands"],
                shortcut: "⇧⌘P",
                systemImage: "chevron.right.square"
            )
        case .newMemo:
            return CommandDescriptor(
                id: self,
                category: .file,
                title: "新規メモ",
                summary: "現在のフォルダにメモを作ります。a/b.md のように書くと途中のフォルダも作られます。",
                keywords: ["new file", "create memo", "touch", "sakusei"],
                shortcut: nil,
                systemImage: "square.and.pencil"
            )
        case .newFolder:
            return CommandDescriptor(
                id: self,
                category: .folder,
                title: "新規フォルダ",
                summary: "現在のフォルダの下にフォルダを作ります。階層をまとめて指定できます。",
                keywords: ["new folder", "mkdir", "create directory"],
                shortcut: nil,
                systemImage: "folder.badge.plus"
            )
        case .renameMemo:
            return CommandDescriptor(
                id: self,
                category: .file,
                title: "メモの名前を変更",
                summary: "表示中のメモをリネームします。並び順とローテーション対象の設定は引き継がれます。",
                keywords: ["rename file", "mv", "henkou"],
                shortcut: nil,
                systemImage: "pencil.line"
            )
        case .renameFolder:
            return CommandDescriptor(
                id: self,
                category: .folder,
                title: "フォルダの名前を変更",
                summary: "選択中のフォルダをリネームします。中のメモの並び順もそのまま移ります。",
                keywords: ["rename folder", "mv directory"],
                shortcut: nil,
                systemImage: "folder.badge.gearshape"
            )
        case .deleteMemo:
            return CommandDescriptor(
                id: self,
                category: .file,
                title: "メモを削除",
                summary: "表示中のメモをゴミ箱へ移します（確認あり）。",
                keywords: ["delete file", "remove", "trash", "sakujo"],
                shortcut: nil,
                systemImage: "trash"
            )
        case .deleteFolder:
            return CommandDescriptor(
                id: self,
                category: .folder,
                title: "フォルダを削除",
                summary: "選択中のフォルダを中身ごとゴミ箱へ移します（確認あり）。",
                keywords: ["delete folder", "remove directory", "trash"],
                shortcut: nil,
                systemImage: "folder.badge.minus"
            )
        case .revealMemo:
            return CommandDescriptor(
                id: self,
                category: .file,
                title: "メモを Finder で表示",
                summary: "表示中のメモを Finder で選択状態にします。",
                keywords: ["reveal in finder", "show in finder"],
                shortcut: nil,
                systemImage: "doc.viewfinder"
            )
        case .revealFolder:
            return CommandDescriptor(
                id: self,
                category: .folder,
                title: "フォルダを Finder で開く",
                summary: "選択中のフォルダを Finder で開きます。",
                keywords: ["open folder", "finder"],
                shortcut: nil,
                systemImage: "folder"
            )
        case .rescan:
            return CommandDescriptor(
                id: self,
                category: .folder,
                title: "再スキャン",
                summary: "Finder 側での追加・削除・リネームを読み直します。",
                keywords: ["rescan", "reload", "refresh"],
                shortcut: nil,
                systemImage: "arrow.clockwise"
            )
        case .nextMemo:
            return CommandDescriptor(
                id: self,
                category: .rotation,
                title: "次のメモへ",
                summary: "ローテーション対象のうち次のメモを表示します。",
                keywords: ["next memo", "forward"],
                shortcut: "⌥⌘→",
                systemImage: "chevron.right"
            )
        case .previousMemo:
            return CommandDescriptor(
                id: self,
                category: .rotation,
                title: "前のメモへ",
                summary: "ローテーション対象のうち前のメモを表示します。",
                keywords: ["previous memo", "back"],
                shortcut: "⌥⌘←",
                systemImage: "chevron.left"
            )
        case .toggleRotationTarget:
            return CommandDescriptor(
                id: self,
                category: .rotation,
                title: "このメモをローテーションに含める / 外す",
                summary: "表示中のメモを巡回の対象から外したり、戻したりします。",
                keywords: ["toggle rotation target", "enable", "disable", "skip"],
                shortcut: nil,
                systemImage: "moon.zzz"
            )
        case .toggleRotation:
            return CommandDescriptor(
                id: self,
                category: .rotation,
                title: "自動ローテーションを切り替え",
                summary: "アイドル後の自動巡回そのものをオン / オフします。",
                keywords: ["toggle rotation", "auto rotate", "pause"],
                shortcut: nil,
                systemImage: "arrow.triangle.2.circlepath"
            )
        case .togglePreview:
            return CommandDescriptor(
                id: self,
                category: .view,
                title: "Markdown プレビューを切り替え",
                summary: "表示中の .md を編集 ⇄ プレビューで切り替えます。",
                keywords: ["toggle preview", "markdown", "render"],
                shortcut: nil,
                systemImage: "eye"
            )
        case .toggleSidebar:
            return CommandDescriptor(
                id: self,
                category: .view,
                title: "フォルダツリーを切り替え",
                summary: "左ペインの表示 / 非表示を切り替えます。",
                keywords: ["toggle sidebar", "tree"],
                shortcut: "⌥⌘1",
                systemImage: "sidebar.left"
            )
        case .togglePin:
            return CommandDescriptor(
                id: self,
                category: .view,
                title: "常に最前面表示を切り替え",
                summary: "ウィンドウを他のアプリより前に固定するかどうかを切り替えます。",
                keywords: ["always on top", "pin", "float"],
                shortcut: nil,
                systemImage: "pin"
            )
        case .openSettings:
            return CommandDescriptor(
                id: self,
                category: .view,
                title: "設定を開く",
                summary: "本文エリアを設定ページに切り替えます。",
                keywords: ["settings", "preferences", "config"],
                shortcut: "⌘,",
                systemImage: "gearshape"
            )
        }
    }
}

enum CommandCatalog {
    /// パレットにも設定ページにも、この順番でそのまま並べる。
    static let all: [CommandDescriptor] = CommandCategory.allCases.flatMap { category in
        CommandID.allCases.map(\.descriptor).filter { $0.category == category }
    }

    static func commands(in category: CommandCategory) -> [CommandDescriptor] {
        all.filter { $0.category == category }
    }

    /// パレットで使えるキー操作。設定ページの説明にもそのまま出す。
    static let keyHints: [KeyHint] = [
        KeyHint(keys: "↑ / ↓（⌃P / ⌃N）", description: "候補を上下に移動"),
        KeyHint(keys: "Tab", description: "選択中の候補を入力欄に取り込んで、さらに絞り込む"),
        KeyHint(keys: "Enter", description: "決定（開く / 実行 / 作成 / 削除の確定）"),
        KeyHint(keys: "Esc", description: "パレットを閉じる")
    ]
}
