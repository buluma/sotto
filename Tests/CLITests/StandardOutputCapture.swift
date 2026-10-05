import Darwin
import Foundation
import os

/// Captures stdout payloads emitted by focused CLI unit tests.
func captureStandardOutput(_ body: () throws -> Void) throws -> String {
    let pipe = Pipe()
    let originalStdout = dup(STDOUT_FILENO)
    guard originalStdout >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let readGroup = DispatchGroup()
    let readQueue = DispatchQueue(label: "sotto.tests.stdout-capture")
    let capturedData = OSAllocatedUnfairLock(initialState: Data())
    readGroup.enter()
    readQueue.async {
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        capturedData.withLock { $0 = bytes }
        readGroup.leave()
    }

    fflush(stdout)
    guard dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) >= 0 else {
        close(originalStdout)
        pipe.fileHandleForWriting.closeFile()
        readGroup.wait()
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    var bodyError: Error?
    do {
        try body()
    } catch {
        bodyError = error
    }

    fflush(stdout)
    guard dup2(originalStdout, STDOUT_FILENO) >= 0 else {
        let restoreErrno = errno
        close(originalStdout)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(restoreErrno))
    }
    close(originalStdout)
    pipe.fileHandleForWriting.closeFile()
    readGroup.wait()

    if let bodyError {
        throw bodyError
    }
    return String(decoding: capturedData.withLock { $0 }, as: UTF8.self)
}

/// Async variant for `AsyncParsableCommand.run()` tests.
/// Keep usage focused: stdout is process-global, so these tests must not run
/// bodies that concurrently print unrelated output.
func captureStandardOutput(
    isolation: isolated (any Actor)? = #isolation,
    _ body: () async throws -> Void
) async throws -> String {
    let pipe = Pipe()
    let originalStdout = dup(STDOUT_FILENO)
    guard originalStdout >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let readTask = Task.detached {
        pipe.fileHandleForReading.readDataToEndOfFile()
    }

    fflush(stdout)
    guard dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) >= 0 else {
        close(originalStdout)
        pipe.fileHandleForWriting.closeFile()
        _ = await readTask.value
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    var bodyError: Error?
    do {
        try await body()
    } catch {
        bodyError = error
    }

    fflush(stdout)
    guard dup2(originalStdout, STDOUT_FILENO) >= 0 else {
        let restoreErrno = errno
        close(originalStdout)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(restoreErrno))
    }
    close(originalStdout)
    pipe.fileHandleForWriting.closeFile()
    let capturedData = await readTask.value

    if let bodyError {
        throw bodyError
    }
    return String(decoding: capturedData, as: UTF8.self)
}
