import DualSenseBridgeCore
import Foundation

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("dualsense-bridge: \(message)\n".utf8))
    exit(code)
}

do {
    let command = try BridgeCommand(parsing: Array(CommandLine.arguments.dropFirst()))
    try CommandRunner().run(command)
} catch let error as CommandLineError {
    fail("\(error)\n\n\(BridgeCommand.usageText)", code: ExitCode.badUsage.status)
} catch let error as ProfileLoadError {
    fail("\(error)", code: ExitCode.badProfile.status)
} catch let error as ExitCode {
    exit(error.status)
} catch {
    fail("\(error)", code: 70)
}
