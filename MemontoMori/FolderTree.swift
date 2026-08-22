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
    func visibleRows(isExpanded: (String) -> Bool) -> [FolderRow] {
        var rows: [FolderRow] = []
        appendRows(to: &rows, depth: 0, isExpanded: isExpanded)
        return rows
    }

    private func appendRows(
        to rows: inout [FolderRow],
        depth: Int,
        isExpanded: (String) -> Bool
    ) {
        rows.append(
            FolderRow(id: id, name: name, depth: depth, hasChildren: hasChildren, isRoot: isRoot)
        )
        guard isExpanded(id) else { return }
        for child in children {
            child.appendRows(to: &rows, depth: depth + 1, isExpanded: isExpanded)
        }
    }
}

/// 左ペインに描画する 1 行分の情報。
struct FolderRow: Identifiable, Equatable {
    let id: String
    let name: String
    let depth: Int
    let hasChildren: Bool
    let isRoot: Bool
}
