// Today's Tasks state, day navigation, persistence (split from AppModel.swift; mechanical move).
import AppKit
import Foundation
import MiranNotesCore
import Observation
import os.log
import SwiftUI

extension AppModel {
    private var isEligibleForTodaysTasksVaultExperience: Bool {
        workspaceScope == .fullVault && !visibleTopLevelFolderEntries.isEmpty
    }

    /// Full vault with visible top-level folders: the vault tray row is shown as a button.
    var showsVaultTrayAsButton: Bool {
        isEligibleForTodaysTasksVaultExperience
    }

    /// Detail column shows the Today’s Tasks page instead of vault-root notes.
    func showsTodaysTasksVaultRootPage(forPane pane: Int) -> Bool {
        guard isEligibleForTodaysTasksVaultExperience,
            workspacePanes.indices.contains(pane),
            workspacePanes[pane].selectedFolderID == FolderCatalog.rootFolderID
        else { return false }
        return true
    }

    func addTodaysTaskRow() -> UUID {
        let id = UUID()
        todaysTasksItems.append(VaultTodaysTaskRow(id: id, lines: [""], isDone: false))
        scheduleTodaysTasksPersist()
        return id
    }

    func setTodaysTaskLine(taskID: UUID, lineIndex: Int, text: String) {
        guard let i = todaysTasksItems.firstIndex(where: { $0.id == taskID }) else { return }
        guard todaysTasksItems[i].lines.indices.contains(lineIndex) else { return }
        todaysTasksItems[i].lines[lineIndex] = text
        scheduleTodaysTasksPersist()
    }

    /// Inserts an empty line after `afterIndex`. Returns the index of the new line.
    func insertTodaysTaskLineAfter(taskID: UUID, afterIndex: Int) -> Int {
        guard let i = todaysTasksItems.firstIndex(where: { $0.id == taskID }) else { return afterIndex + 1 }
        var row = todaysTasksItems[i]
        let insertAt = min(max(afterIndex + 1, 0), row.lines.count)
        row.lines.insert("", at: insertAt)
        row.lineIDs.insert(UUID(), at: insertAt)
        todaysTasksItems[i] = row
        scheduleTodaysTasksPersist()
        return insertAt
    }

    /// Removes a detail line (`lineIndex` > 0). Keeps at least one line per task.
    func removeTodaysTaskLine(taskID: UUID, lineIndex: Int) {
        guard lineIndex > 0 else { return }
        guard let i = todaysTasksItems.firstIndex(where: { $0.id == taskID }) else { return }
        var row = todaysTasksItems[i]
        guard row.lines.indices.contains(lineIndex) else { return }
        row.lines.remove(at: lineIndex)
        row.lineIDs.remove(at: lineIndex)
        if row.lines.isEmpty {
            row.lines = [""]
            row.lineIDs = [UUID()]
        }
        todaysTasksItems[i] = row
        scheduleTodaysTasksPersist()
    }

    func toggleTodaysTaskDone(id: UUID) {
        guard let i = todaysTasksItems.firstIndex(where: { $0.id == id }) else { return }
        todaysTasksItems[i].isDone.toggle()
        scheduleTodaysTasksPersist()
    }

    func bindingForTodaysTaskLine(taskID: UUID, lineIndex: Int) -> Binding<String> {
        Binding(
            get: {
                guard let row = self.todaysTasksItems.first(where: { $0.id == taskID }),
                    row.lines.indices.contains(lineIndex)
                else { return "" }
                return row.lines[lineIndex]
            },
            set: { self.setTodaysTaskLine(taskID: taskID, lineIndex: lineIndex, text: $0) }
        )
    }

    var todaysTasksSelectedDayDisplayShort: String {
        todaysTasksSelectedDay.displayShortYYMMDD(calendar: Self.vaultTasksCalendar())
    }

    var canGoToPreviousTodaysTasksDay: Bool {
        VaultTasksDayNavigation.previous(before: todaysTasksSelectedDay, knownSorted: todaysTasksKnownDays) != nil
    }

    var canGoToNextTodaysTasksDay: Bool {
        VaultTasksDayNavigation.next(after: todaysTasksSelectedDay, knownSorted: todaysTasksKnownDays) != nil
    }

    func goToPreviousTodaysTasksDay() {
        guard let prev = VaultTasksDayNavigation.previous(before: todaysTasksSelectedDay, knownSorted: todaysTasksKnownDays) else { return }
        persistTodaysTasksImmediatelyForSelectedDay()
        todaysTasksSelectedDay = prev
        todaysTasksItems = VaultTodaysTasksDayStore.load(day: prev, vaultURL: repository.vaultURL)
    }

    func goToNextTodaysTasksDay() {
        guard let next = VaultTasksDayNavigation.next(after: todaysTasksSelectedDay, knownSorted: todaysTasksKnownDays) else { return }
        persistTodaysTasksImmediatelyForSelectedDay()
        todaysTasksSelectedDay = next
        todaysTasksItems = VaultTodaysTasksDayStore.load(day: next, vaultURL: repository.vaultURL)
    }

    /// Call when the app may have crossed midnight (e.g. scene became active). Snaps selection to wall-clock today and ensures that page exists.
    func refreshTodaysTasksIfCalendarDayChanged() {
        let cal = Self.vaultTasksCalendar()
        let today = VaultTasksCalendarDay.today(calendar: cal)
        guard today != todaysTasksSelectedDay else { return }
        persistTodaysTasksImmediatelyForSelectedDay()
        do {
            var known = try VaultTodaysTasksIndexStore.loadOrBootstrap(vaultURL: repository.vaultURL, calendar: cal)
            if !known.contains(today) {
                try VaultTodaysTasksDayStore.save(day: today, items: [], vaultURL: repository.vaultURL)
                known = try VaultTodaysTasksIndexStore.insertDayIfMissing(today, vaultURL: repository.vaultURL, existing: known)
            }
            todaysTasksKnownDays = known
            todaysTasksSelectedDay = today
            todaysTasksItems = VaultTodaysTasksDayStore.load(day: today, vaultURL: repository.vaultURL)
            if todaysTasksItems.isEmpty, AppSettings.shared.autoRollOverTasks {
                rollOverIncompleteTasksIntoSelectedDay()
            }
        } catch {
            userAlert = .message("Could not update Today’s Tasks for the new day: \(error.localizedDescription)")
        }
    }

    func scheduleTodaysTasksPersist() {
        todaysTasksPersistTask?.cancel()
        todaysTasksPersistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(autosaveDebounceMilliseconds))
            guard !Task.isCancelled else { return }
            let day = self.todaysTasksSelectedDay
            let items = self.todaysTasksItems
            do {
                try VaultTodaysTasksDayStore.save(day: day, items: items, vaultURL: self.repository.vaultURL)
                self.registerTodaysTasksDayInIndexIfNeeded(day, hasItems: !items.isEmpty)
            } catch {
                userAlert = .message("Could not save Today’s Tasks: \(error.localizedDescription)")
            }
        }
    }

    /// Freshly written day pages become navigable: keep the index in sync with day files.
    func registerTodaysTasksDayInIndexIfNeeded(_ day: VaultTasksCalendarDay, hasItems: Bool) {
        guard hasItems, !todaysTasksKnownDays.contains(day) else { return }
        if let updated = try? VaultTodaysTasksIndexStore.insertDayIfMissing(
            day,
            vaultURL: repository.vaultURL,
            existing: todaysTasksKnownDays
        ) {
            todaysTasksKnownDays = updated
        }
    }

    // MARK: - Free day navigation & rollover

    /// Jumps to any calendar day (empty days show an empty editable list; the day is indexed once it has content).
    func goToTodaysTasksDay(_ day: VaultTasksCalendarDay) {
        guard day != todaysTasksSelectedDay else { return }
        persistTodaysTasksImmediatelyForSelectedDay()
        todaysTasksSelectedDay = day
        todaysTasksItems = VaultTodaysTasksDayStore.load(day: day, vaultURL: repository.vaultURL)
    }

    func goToTodaysTasksToday() {
        goToTodaysTasksDay(VaultTasksCalendarDay.today(calendar: Self.vaultTasksCalendar()))
    }

    var todaysTasksSelectedDayIsToday: Bool {
        todaysTasksSelectedDay == VaultTasksCalendarDay.today(calendar: Self.vaultTasksCalendar())
    }

    /// Most recent prior day that still has unfinished tasks (rollover source), if any.
    var todaysTasksRolloverSourceDay: VaultTasksCalendarDay? {
        for day in todaysTasksKnownDays.reversed() where day < todaysTasksSelectedDay {
            let items = VaultTodaysTasksDayStore.load(day: day, vaultURL: repository.vaultURL)
            let unfinished = items.filter { !$0.isDone }
            if !unfinished.isEmpty { return day }
            if !items.isEmpty { return nil }  // most recent day with content had nothing open
        }
        return nil
    }

    /// Copies unfinished tasks from the most recent prior day with content into the selected day,
    /// tagging their origin. Rows whose primary line already exists here are skipped.
    func rollOverIncompleteTasksIntoSelectedDay() {
        guard let sourceDay = todaysTasksRolloverSourceDay else { return }
        let sourceItems = VaultTodaysTasksDayStore.load(day: sourceDay, vaultURL: repository.vaultURL)
        let existingPrimaryLines = Set(todaysTasksItems.map { $0.lines.first ?? "" })
        var appended = false
        for item in sourceItems where !item.isDone {
            let primary = item.lines.first ?? ""
            guard !primary.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard !existingPrimaryLines.contains(primary) else { continue }
            todaysTasksItems.append(
                VaultTodaysTaskRow(
                    id: UUID(),
                    lines: item.lines,
                    isDone: false,
                    rolledFromDayKey: sourceDay.storageKey,
                    sourceNoteID: item.sourceNoteID,
                    sourceBlockID: item.sourceBlockID
                )
            )
            appended = true
        }
        if appended {
            persistTodaysTasksImmediatelyForSelectedDay()
            registerTodaysTasksDayInIndexIfNeeded(todaysTasksSelectedDay, hasItems: true)
        }
    }

    // MARK: - Note integration (one-way; no live sync)

    /// "Add to Today's Tasks" from a note's task block: appends a linked row to **today**.
    func addNoteBlockToTodaysTasks(noteID: UUID, blockID: String, text: String) {
        let today = VaultTasksCalendarDay.today(calendar: Self.vaultTasksCalendar())
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = trimmed.isEmpty ? "(untitled task)" : trimmed
        if todaysTasksSelectedDay == today {
            todaysTasksItems.append(
                VaultTodaysTaskRow(id: UUID(), lines: [line], isDone: false, sourceNoteID: noteID, sourceBlockID: blockID)
            )
            persistTodaysTasksImmediatelyForSelectedDay()
            registerTodaysTasksDayInIndexIfNeeded(today, hasItems: true)
        } else {
            var items = VaultTodaysTasksDayStore.load(day: today, vaultURL: repository.vaultURL)
            items.append(
                VaultTodaysTaskRow(id: UUID(), lines: [line], isDone: false, sourceNoteID: noteID, sourceBlockID: blockID)
            )
            do {
                try VaultTodaysTasksDayStore.save(day: today, items: items, vaultURL: repository.vaultURL)
                registerTodaysTasksDayInIndexIfNeeded(today, hasItems: true)
            } catch {
                userAlert = .message("Could not add the task to Today’s Tasks: \(error.localizedDescription)")
                return
            }
        }
    }

    /// Opens the origin note of a linked row and scrolls to its block when it still exists.
    func openTodaysTaskSource(_ row: VaultTodaysTaskRow) {
        guard let noteID = row.sourceNoteID else { return }
        guard noteSummaries.contains(where: { $0.noteID == noteID }) else {
            userAlert = .message("The note this task came from isn’t in the vault anymore.")
            return
        }
        let pane = activePaneIndex
        let blockID = row.sourceBlockID
        Task { @MainActor in
            if let blockID,
               let result = try? await repository.loadNote(noteID: noteID),
               let block = result.document.metadata.blocks.first(where: { $0.id == blockID }),
               !block.range.isEmpty {
                pendingEditorScroll = PendingEditorScroll(noteID: noteID, range: block.range)
            } else {
                pendingEditorScroll = nil
            }
            changeSelection(noteID: noteID, pane: pane)
        }
    }

    /// Explicit cross-file completion: marks the origin task block done in its note.
    /// Uses the open pane's pipeline when the note is active there; otherwise load → engine → save.
    func markTodaysTaskDoneInSourceNote(_ row: VaultTodaysTaskRow) {
        guard let noteID = row.sourceNoteID, let blockID = row.sourceBlockID else { return }
        if let pane = workspacePanes.firstIndex(where: { $0.activeDocument?.metadata.noteID == noteID }) {
            if pane != activePaneIndex { activatePaneForEditingSync(pane) }
            _ = apply([.setBlockDone(blockID: blockID, isDone: true)])
            return
        }
        Task { @MainActor in
            do {
                let result = try await repository.loadNote(noteID: noteID)
                guard result.document.metadata.blocks.contains(where: { $0.id == blockID && $0.type == .taskItem }) else {
                    userAlert = .message("The task block no longer exists in its note.")
                    return
                }
                let updated = EditCommandEngine.apply(.setBlockDone(blockID: blockID, isDone: true), to: result.document)
                guard let path = try await repository.loadManifest().entry(noteID: noteID)?.relativePath else { return }
                _ = try await repository.save(updated, asBaseName: path)
            } catch {
                userAlert = .message("Could not update the note: \(error.localizedDescription)")
            }
        }
    }

    func loadVaultTodaysTasksStateAfterPreferences() throws {
        let cal = Self.vaultTasksCalendar()
        let vaultURL = repository.vaultURL
        var known = try VaultTodaysTasksIndexStore.loadOrBootstrap(vaultURL: vaultURL, calendar: cal)
        let today = VaultTasksCalendarDay.today(calendar: cal)
        if !known.contains(today) {
            try VaultTodaysTasksDayStore.save(day: today, items: [], vaultURL: vaultURL)
            known = try VaultTodaysTasksIndexStore.insertDayIfMissing(today, vaultURL: vaultURL, existing: known)
        }
        todaysTasksKnownDays = known
        todaysTasksSelectedDay = today
        todaysTasksItems = VaultTodaysTasksDayStore.load(day: today, vaultURL: vaultURL)
    }

    func persistTodaysTasksImmediatelyForSelectedDay() {
        todaysTasksPersistTask?.cancel()
        todaysTasksPersistTask = nil
        do {
            try VaultTodaysTasksDayStore.save(
                day: todaysTasksSelectedDay,
                items: todaysTasksItems,
                vaultURL: repository.vaultURL
            )
        } catch {
            userAlert = .message("Could not save Today’s Tasks: \(error.localizedDescription)")
        }
    }
}
