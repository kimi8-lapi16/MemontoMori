import Foundation

/// メモ用ルートフォルダを頂点とした、フォルダ階層の 1 ノード。
///
/// `MemoStore.availableSubdirectories` は「ルートからの相対パス」のフラットな配列なので、
/// 左ペインで木として描けるようにここで組み立て直す。
struct FolderNode: Identifiable, Equatable {
    /// ルートからの相対パス。ルート自身は空文字。
    let id: String
    let name: String
    let children: [FolderNode]

    var isRoot: Bool { id.isEmpty }
    var hasChildren: Bool { !children.isEmpty }

    static func build(rootName: String, relativePaths: [String]) -> FolderNode {
        // 途中のフォルダが列挙から漏れていても木が途切れないよう、祖先を補完しておく。
        var allPaths: Set<String> = []
        for path in relativePaths {
            var accumulated: [String] = []
            for component in path.split(separator: "/") {
                accumulated.append(String(component))
                allPaths.insert(accumulated.joined(separator: "/"))
            }
        }

        var childPaths: [String: [String]] = [:]
        for path in allPaths {
            var components = path.split(separator: "/").map(String.init)
            components.removeLast()
            let parent = components.joined(separator: "/")
            childPaths[parent, default: []].append(path)
        }

        func makeNode(path: String, name: String) -> FolderNode {
            let children = (childPaths[path] ?? [])
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { childPath in
                    makeNode(path: childPath, name: Self.leafName(of: childPath))
                }
            return FolderNode(id: path, name: name, children: children)
        }

        return makeNode(path: "", name: rootName)
    }

    static func leafName(of relativePath: String) -> String {
        relativePath.split(separator: "/").last.map(String.init) ?? relativePath
    }

    /// 展開状態にしたがって、実際に描画する行だけを上から順に並べる。
    ///
    /// - Parameters:
    ///   - isExpanded: そのフォルダが開かれているか。
    ///   - memoCount: フォルダが持つメモの数（開かなくても件数を出すため）。
    ///   - memos: そのフォルダの直下に並べるメモ。ローテーション対象フォルダ以外は空を返す。
    func rows(
        isExpanded: (String) -> Bool,
        memoCount: (String) -> Int,
        memos: (String) -> [MemoEntry]
    ) -> [SidebarRow] {
        var rows: [SidebarRow] = []
        appendRows(to: &rows, depth: 0, isExpanded: isExpanded, memoCount: memoCount, memos: memos)
        return rows
    }

    private func appendRows(
        to rows: inout [SidebarRow],
        depth: Int,
        isExpanded: (String) -> Bool,
        memoCount: (String) -> Int,
        memos: (String) -> [MemoEntry]
    ) {
        let ownMemos = memos(id)
        rows.append(
            SidebarRow(
                id: "dir:" + id,
                folderPath: id,
                name: name,
                depth: depth,
                kind: .folder(
                    hasChildren: hasChildren || !ownMemos.isEmpty,
                    isRoot: isRoot,
                    memoCount: memoCount(id)
                )
            )
        )
        guard isExpanded(id) else { return }

        // IDE と同じくフォルダを先、ファイルを後に並べる。
        for child in children {
            child.appendRows(
                to: &rows,
                depth: depth + 1,
                isExpanded: isExpanded,
                memoCount: memoCount,
                memos: memos
            )
        }
        for memo in ownMemos {
            rows.append(
                SidebarRow(
                    id: "memo:" + (id.isEmpty ? memo.id : id + "/" + memo.id),
                    folderPath: id,
                    name: memo.id,
                    depth: depth + 1,
                    kind: .memo(isEnabled: memo.isEnabled)
                )
            )
        }
    }
}

/// 左ペインに描画する 1 行分の情報。
struct SidebarRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case folder(hasChildren: Bool, isRoot: Bool, memoCount: Int)
        case memo(isEnabled: Bool)
    }

    /// 行の一意な ID。フォルダ行とメモ行で名前が衝突しないよう接頭辞を付ける。
    let id: String
    /// フォルダ行は自身の相対パス、メモ行は置かれているフォルダの相対パス。
    let folderPath: String
    /// フォルダ行はフォルダ名、メモ行はファイル名（拡張子込み）。
    let name: String
    let depth: Int
    let kind: Kind
}
