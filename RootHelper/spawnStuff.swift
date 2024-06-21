//
//  spawnRoot.swift
//  PurePKG
//
//  Created by Lrdsnow on 1/15/24.
//

import Foundation

#if os(macOS)
@discardableResult
func spawnRootHelper(args: [String]) -> (Int32, String, String) {
    let process = Process()
    process.executableURL = Bundle.main.executableURL
    process.arguments = [ "roothelper" ] + args

    let outputPipe = Pipe()
    let errorPipe = Pipe()

    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
    } catch {
        print("Error: \(error)")
        return (-1, "", "")
    }

    process.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

    let outputString = String(data: outputData, encoding: .utf8) ?? ""
    let errorString = String(data: errorData, encoding: .utf8) ?? ""

    let status = process.terminationStatus

    return (status, outputString, errorString)
}
#else
@discardableResult
func spawnRootHelper(args: [String]) -> (Int, String, String) {
    #if targetEnvironment(simulator)
    return (0, "", "")
    #else
    let argsReal = [ "RootHelper" ] + args;
    let argv: [UnsafeMutablePointer<CChar>?] = argsReal.map { $0.withCString(strdup) }
    defer { for case let arg? in argv { free(arg) } }
    
    let env: [String] = [];
    let envp: [UnsafeMutablePointer<CChar>?] = env.map { $0.withCString(strdup) }
    defer { for case let env? in envp { free(env) } }
    
    var stdoutPipe: [Int32] = [0, 0];
    var stderrPipe: [Int32] = [0, 0];
    
    pipe(&stdoutPipe)
    pipe(&stderrPipe)

    guard fcntl(stdoutPipe[0], F_SETFL, O_NONBLOCK) != -1 else {
        return (-1, "pipe stdout failed", "Error = \(errno), \(String(cString: strerror(errno)))");
    }
    
    guard fcntl(stderrPipe[0], F_SETFL, O_NONBLOCK) != -1 else {
        return (-1, "pipe stderr failed", "Error = \(errno), \(String(cString: strerror(errno)))");
    }
    
    var actions: posix_spawn_file_actions_t?
    
    custom_posix_spawn_file_actions_init(&actions);
    custom_posix_spawn_file_actions_addclose(&actions, stdoutPipe[0]);
    custom_posix_spawn_file_actions_addclose(&actions, stderrPipe[0]);
    custom_posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO);
    custom_posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO);
    custom_posix_spawn_file_actions_addclose(&actions, stdoutPipe[1]);
    custom_posix_spawn_file_actions_addclose(&actions, stderrPipe[1]);
    
    
    var pid: pid_t = 0
    
    var attr: posix_spawnattr_t?
    custom_posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, 99, UInt32(POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE));
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
    
    let spawnStatus = custom_posix_spawn(&pid, Bundle.main.executablePath, &actions, &attr, argv + [nil], envp + [nil]);
    
    custom_posix_spawnattr_destroy(&attr);
    custom_posix_spawn_file_actions_destroy(&actions);
    close(stdoutPipe[1]);
    close(stderrPipe[1]);
    
    if spawnStatus != 0 {
        NSLog("%@", "posix_spawn failed!\n Error = \(errno)  \(String(cString: strerror(spawnStatus))) \(String(cString: strerror(errno)))\n)");
        return (Int(spawnStatus), "posix_spawn failed!", "Error = \(errno) \(String(cString: strerror(errno)))\n)")
    }
    
    var stdoutStr = "";
    var stderrStr = "";

    let mutex = DispatchSemaphore(value: 0);

    let readQueue = DispatchQueue(label: "uwu.lrdsnow.purepkg.command",
                                  qos: .userInitiated,
                                  attributes: .concurrent,
                                  autoreleaseFrequency: .inherit,
                                  target: nil);

    let stdoutSource = DispatchSource.makeReadSource(fileDescriptor: stdoutPipe[0], queue: readQueue);
    let stderrSource = DispatchSource.makeReadSource(fileDescriptor: stderrPipe[0], queue: readQueue);
    
    let bufsiz: size_t = Int(BUFSIZ);
    
    stdoutSource.setCancelHandler {
        close(stdoutPipe[0])
        mutex.signal()
    }
    stderrSource.setCancelHandler {
        close(stderrPipe[0])
        mutex.signal()
    }
    
    stdoutSource.setEventHandler {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufsiz);
        defer { buffer.deallocate() }
        let didRead = read(stdoutPipe[0], buffer, bufsiz);
        guard didRead > 0 else {
            if (didRead == -1 && errno == EAGAIN) {
                return;
            }
            
            stdoutSource.cancel();
            return;
        }
        
        let cStrArray = Array(UnsafeBufferPointer(start: buffer, count: didRead)) + [nil];
        
        cStrArray.withUnsafeBufferPointer { ptr in
            let str = String(cString: unsafeBitCast(ptr.baseAddress, to: UnsafePointer<CChar>.self));
            stdoutStr += str;
        }
    }
    
    stderrSource.setEventHandler {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufsiz);
        defer { buffer.deallocate() }
        let didRead = read(stderrPipe[0], buffer, bufsiz);
        guard didRead > 0 else {
            if (didRead == -1 && errno == EAGAIN) {
                return;
            }
            
            stderrSource.cancel();
            return;
        }
        
        let cStrArray = Array(UnsafeBufferPointer(start: buffer, count: didRead)) + [nil];
        
        cStrArray.withUnsafeBufferPointer { ptr in
            let str = String(cString: unsafeBitCast(ptr.baseAddress, to: UnsafePointer<CChar>.self));
            stderrStr += str;
        }
    }
    
    stdoutSource.resume();
    stderrSource.resume();

    mutex.wait();
    mutex.wait();
    
    var status: Int32 = 0
    waitpid(pid, &status, 0);
    
    let desc_cstring: UnsafeMutablePointer<CChar> = waitpid_decode(status);
    let desc = String(cString: desc_cstring);
    free(desc_cstring);
    
    NSLog("%@", "spawnRootHelper: return status: \(status), description: \(desc)");
    NSLog("%@", "rootHelper stdout = \n\(stdoutStr)");
    NSLog("%@", "rootHelper stderr = \n\(stderrStr)");
    
    return (Int(status), stdoutStr, stderrStr);
    #endif
}
#endif

@discardableResult
func spawnAsRoot(command: String, args: [String]) -> (Int, String, String) {
    let argv: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString(strdup) }
    defer { for case let arg? in argv { free(arg) } }
    
    let env: [String] = [];
    let envp: [UnsafeMutablePointer<CChar>?] = env.map { $0.withCString(strdup) }
    defer { for case let env? in envp { free(env) } }
    
    var stdoutPipe: [Int32] = [0, 0];
    var stderrPipe: [Int32] = [0, 0];
    
    pipe(&stdoutPipe)
    pipe(&stderrPipe)

    guard fcntl(stdoutPipe[0], F_SETFL, O_NONBLOCK) != -1 else {
        return (-1, "pipe stdout failed", "Error = \(errno), \(String(cString: strerror(errno)))");
    }
    
    guard fcntl(stderrPipe[0], F_SETFL, O_NONBLOCK) != -1 else {
        return (-1, "pipe stderr failed", "Error = \(errno), \(String(cString: strerror(errno)))");
    }
    
    var actions: posix_spawn_file_actions_t?
    
    custom_posix_spawn_file_actions_init(&actions);
    custom_posix_spawn_file_actions_addclose(&actions, stdoutPipe[0]);
    custom_posix_spawn_file_actions_addclose(&actions, stderrPipe[0]);
    custom_posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO);
    custom_posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO);
    custom_posix_spawn_file_actions_addclose(&actions, stdoutPipe[1]);
    custom_posix_spawn_file_actions_addclose(&actions, stderrPipe[1]);
    
    
    var pid: pid_t = 0
    
    var attr: posix_spawnattr_t?
    custom_posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, 99, UInt32(POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE));
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
    
    let spawnStatus = custom_posix_spawn(&pid, command, &actions, &attr, argv + [nil], envp + [nil]);
    
    custom_posix_spawnattr_destroy(&attr);
    custom_posix_spawn_file_actions_destroy(&actions);
    close(stdoutPipe[1]);
    close(stderrPipe[1]);
    
    if spawnStatus != 0 {
        NSLog("%@", "posix_spawn failed!\n Error = \(errno)  \(String(cString: strerror(spawnStatus))) \(String(cString: strerror(errno)))\n)");
        return (Int(spawnStatus), "posix_spawn failed!", "Error = \(errno) \(String(cString: strerror(errno)))\n)")
    }
    
    var stdoutStr = "";
    var stderrStr = "";

    let mutex = DispatchSemaphore(value: 0);

    let readQueue = DispatchQueue(label: "uwu.lrdsnow.purepkg.command",
                                  qos: .userInitiated,
                                  attributes: .concurrent,
                                  autoreleaseFrequency: .inherit,
                                  target: nil);

    let stdoutSource = DispatchSource.makeReadSource(fileDescriptor: stdoutPipe[0], queue: readQueue);
    let stderrSource = DispatchSource.makeReadSource(fileDescriptor: stderrPipe[0], queue: readQueue);
    
    let bufsiz: size_t = Int(BUFSIZ);
    
    stdoutSource.setCancelHandler {
        close(stdoutPipe[0])
        mutex.signal()
    }
    stderrSource.setCancelHandler {
        close(stderrPipe[0])
        mutex.signal()
    }
    
    stdoutSource.setEventHandler {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufsiz);
        defer { buffer.deallocate() }
        let didRead = read(stdoutPipe[0], buffer, bufsiz);
        guard didRead > 0 else {
            if (didRead == -1 && errno == EAGAIN) {
                return;
            }
            
            stdoutSource.cancel();
            return;
        }
        
        let cStrArray = Array(UnsafeBufferPointer(start: buffer, count: didRead)) + [nil];
        
        cStrArray.withUnsafeBufferPointer { ptr in
            let str = String(cString: unsafeBitCast(ptr.baseAddress, to: UnsafePointer<CChar>.self));
            stdoutStr += str;
        }
    }
    
    stderrSource.setEventHandler {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufsiz);
        defer { buffer.deallocate() }
        let didRead = read(stderrPipe[0], buffer, bufsiz);
        guard didRead > 0 else {
            if (didRead == -1 && errno == EAGAIN) {
                return;
            }
            
            stderrSource.cancel();
            return;
        }
        
        let cStrArray = Array(UnsafeBufferPointer(start: buffer, count: didRead)) + [nil];
        
        cStrArray.withUnsafeBufferPointer { ptr in
            let str = String(cString: unsafeBitCast(ptr.baseAddress, to: UnsafePointer<CChar>.self));
            stderrStr += str;
        }
    }
    
    stdoutSource.resume();
    stderrSource.resume();

    mutex.wait();
    mutex.wait();
    
    var status: Int32 = 0
    waitpid(pid, &status, 0);
    
    let desc_cstring: UnsafeMutablePointer<CChar> = waitpid_decode(status);
    let desc = String(cString: desc_cstring);
    free(desc_cstring);
    
    NSLog("%@", "spawnAsRoot: return status: \(status), description: \(desc)");
    NSLog("%@", "spawnAsRoot stdout = \n\(stdoutStr)");
    NSLog("%@", "spawnAsRoot stderr = \n\(stderrStr)");
    
    return (Int(status), stdoutStr, stderrStr);
}
