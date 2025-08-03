import AppKit
import Contacts
import SwiftUI

class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()
    
    @Published private(set) var userProfileImage: NSImage?
    @Published private(set) var userName: String = ""
    
    private init() {
        loadUserProfile()
    }
    
    func loadUserProfile() {
        DispatchQueue.global(qos: .background).async {
            let image = self.fetchUserProfileImage()
            let name = self.fetchUserName()
            
            DispatchQueue.main.async {
                self.userProfileImage = image
                self.userName = name
                AppLogger.shared.info("User profile loaded: \(name)")
            }
        }
    }
    
    private func fetchUserProfileImage() -> NSImage? {
        // Method 1: Try to get from Contacts framework
        if let contactImage = getContactsProfileImage() {
            return contactImage
        }
        
        // Method 2: Try to get from AddressBook (deprecated but might still work)
        if let addressBookImage = getAddressBookProfileImage() {
            return addressBookImage
        }
        
        // Method 3: Try to get from System Preferences cache
        if let systemImage = getSystemProfileImage() {
            return systemImage
        }
        
        // Method 4: Try to get from Directory Services
        if let directoryImage = getDirectoryServicesImage() {
            return directoryImage
        }
        
        // Fallback: Return default user icon
        return getDefaultUserIcon()
    }
    
    private func fetchUserName() -> String {
        // Try to get full name from various sources
        
        // Method 1: From NSFullUserName()
        let fullName = NSFullUserName()
        if !fullName.isEmpty && fullName != NSUserName() {
            return fullName
        }
        
        // Method 2: From Contacts framework
        if let contactName = getContactsUserName() {
            return contactName
        }
        
        // Method 3: From Directory Services
        if let directoryName = getDirectoryServicesName() {
            return directoryName
        }
        
        // Fallback: Use username
        return NSUserName()
    }
    
    private func getContactsProfileImage() -> NSImage? {
        let store = CNContactStore()
        
        // Check authorization status first
        let authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        
        switch authorizationStatus {
        case .authorized:
            // Permission granted, proceed with access
            break
        case .notDetermined:
            // Permission not yet requested - request it synchronously for this use case
            var granted = false
            let semaphore = DispatchSemaphore(value: 0)
            
            store.requestAccess(for: .contacts) { success, error in
                granted = success
                if let error = error {
                    AppLogger.shared.error("Error requesting contacts access: \(error)")
                }
                semaphore.signal()
            }
            
            semaphore.wait()
            
            if !granted {
                AppLogger.shared.info("Contacts access denied by user - skipping contact image lookup")
                return nil
            }
        case .denied, .restricted:
            AppLogger.shared.info("Contacts access denied - skipping contact image lookup")
            return nil
        @unknown default:
            AppLogger.shared.info("Unknown contacts authorization status - skipping contact image lookup")
            return nil
        }
        
        let keys = [CNContactImageDataKey, CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor]
        
        do {
            // Try to find the current user in contacts
            let predicate = CNContact.predicateForContacts(matchingName: NSFullUserName())
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            
            for contact in contacts {
                if let imageData = contact.imageData,
                   let image = NSImage(data: imageData) {
                    AppLogger.shared.info("Successfully loaded profile image from Contacts")
                    return image
                }
            }
            
            // If no matches by name, try getting "Me" card
            if let meContact = getMeContact(store: store, keys: keys),
               let imageData = meContact.imageData,
               let image = NSImage(data: imageData) {
                AppLogger.shared.info("Successfully loaded profile image from Contacts 'Me' card")
                return image
            }
            
        } catch {
            AppLogger.shared.error("Failed to access contacts: \(error)")
        }
        
        return nil
    }
    
    private func getMeContact(store: CNContactStore, keys: [CNKeyDescriptor]) -> CNContact? {
        // Try to get the "Me" contact card
        do {
            if #available(macOS 10.15, *) {
                // Use newer API
                let request = CNContactFetchRequest(keysToFetch: keys)
                var meContact: CNContact?
                
                try store.enumerateContacts(with: request) { contact, stop in
                    // Look for indicators that this might be the user's card
                    let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                    if fullName == NSFullUserName() || contact.imageData != nil {
                        meContact = contact
                        stop.pointee = true
                    }
                }
                
                return meContact
            }
        } catch {
            AppLogger.shared.error("Failed to enumerate contacts: \(error)")
        }
        
        return nil
    }
    
    private func getContactsUserName() -> String? {
        let store = CNContactStore()
        
        // Check authorization status first
        let authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        
        switch authorizationStatus {
        case .authorized:
            // Permission granted, proceed with access
            break
        case .notDetermined:
            // Permission not yet requested - request it synchronously for this use case
            var granted = false
            let semaphore = DispatchSemaphore(value: 0)
            
            store.requestAccess(for: .contacts) { success, error in
                granted = success
                if let error = error {
                    AppLogger.shared.error("Error requesting contacts access: \(error)")
                }
                semaphore.signal()
            }
            
            semaphore.wait()
            
            if !granted {
                AppLogger.shared.info("Contacts access denied by user - skipping contact name lookup")
                return nil
            }
        case .denied, .restricted:
            AppLogger.shared.info("Contacts access denied - skipping contact name lookup")
            return nil
        @unknown default:
            AppLogger.shared.info("Unknown contacts authorization status - skipping contact name lookup")
            return nil
        }
        
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor]
        
        do {
            let predicate = CNContact.predicateForContacts(matchingName: NSFullUserName())
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
            
            if let contact = contacts.first {
                let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                if !fullName.isEmpty {
                    AppLogger.shared.info("Successfully loaded user name from Contacts")
                    return fullName
                }
            }
        } catch {
            AppLogger.shared.error("Failed to get user name from contacts: \(error)")
        }
        
        return nil
    }
    
    private func getAddressBookProfileImage() -> NSImage? {
        // Try legacy AddressBook approach (might work on older systems)
        let script = """
        tell application "Contacts"
            try
                set meCard to my card
                if image of meCard is not missing value then
                    return image of meCard
                end if
            on error
                return missing value
            end try
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            _ = appleScript.executeAndReturnError(&error)
            if error == nil {
                // AppleScript results don't have a .data property like that
                // This approach won't work, so skip this method
                return nil
            }
        }
        
        return nil
    }
    
    private func getSystemProfileImage() -> NSImage? {
        // Try to get profile image from system preferences cache
        let userImagePaths = [
            "/Library/User Pictures/\(NSUserName()).tif",
            "/Library/User Pictures/\(NSUserName()).png",
            "/Library/User Pictures/\(NSUserName()).jpg",
            "/Library/User Pictures/\(NSUserName()).jpeg",
            "/var/db/dslocal/nodes/Default/users/\(NSUserName()).plist",
        ]
        
        for path in userImagePaths {
            if FileManager.default.fileExists(atPath: path) {
                if let image = NSImage(contentsOfFile: path) {
                    return image
                }
            }
        }
        
        // Try to read from user's directory services record
        let task = Process()
        task.launchPath = "/usr/bin/dscl"
        task.arguments = [".", "-read", "/Users/\(NSUserName())", "JPEGPhoto"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Parse the JPEG data from the output
            if let jpegData = parseJPEGFromDSCLOutput(output) {
                return NSImage(data: jpegData)
            }
        }
        
        return nil
    }
    
    private func getDirectoryServicesImage() -> NSImage? {
        // Try using DirectoryServices framework
        let script = """
        do shell script "dscl . -read /Users/\(NSUserName()) JPEGPhoto | tail -1 | xxd -r -p" as string
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            _ = appleScript.executeAndReturnError(&error)
            if error == nil {
                // AppleScript approach for getting image data is complex
                // Skip this approach for now
                return nil
            }
        }
        
        return nil
    }
    
    private func getDirectoryServicesName() -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/dscl"
        task.arguments = [".", "-read", "/Users/\(NSUserName())", "RealName"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Parse the real name from the output
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("RealName:") {
                    let name = line.replacingOccurrences(of: "RealName:", with: "").trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        return name
                    }
                }
            }
        }
        
        return nil
    }
    
    private func parseJPEGFromDSCLOutput(_ output: String) -> Data? {
        // Parse hex-encoded JPEG data from dscl output
        let lines = output.components(separatedBy: .newlines)
        var hexString = ""
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.allSatisfy({ $0.isHexDigit || $0 == " " }) {
                hexString += trimmed.replacingOccurrences(of: " ", with: "")
            }
        }
        
        if !hexString.isEmpty {
            return Data(fromHexString: hexString)
        }
        
        return nil
    }
    
    private func getDefaultUserIcon() -> NSImage? {
        // Return a nice default user icon
        if let systemIcon = NSImage(named: "NSUser") {
            return systemIcon
        }
        
        // Create a custom default user icon
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Draw a circle with user icon
        let rect = NSRect(origin: .zero, size: size)
        let circlePath = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
        
        NSColor.systemBlue.setFill()
        circlePath.fill()
        
        // Draw a simple user silhouette
        NSColor.white.setFill()
        let headRect = NSRect(x: 22, y: 36, width: 20, height: 20)
        let headPath = NSBezierPath(ovalIn: headRect)
        headPath.fill()
        
        let bodyRect = NSRect(x: 16, y: 8, width: 32, height: 32)
        let bodyPath = NSBezierPath(ovalIn: bodyRect)
        bodyPath.fill()
        
        image.unlockFocus()
        return image
    }
}

extension Data {
    init?(fromHexString hex: String) {
        let len = hex.count
        if len % 2 != 0 { return nil }
        
        var data = Data()
        var index = hex.startIndex
        
        for _ in 0..<len/2 {
            let nextIndex = hex.index(index, offsetBy: 2)
            let byteString = String(hex[index..<nextIndex])
            
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            
            index = nextIndex
        }
        
        self = data
    }
}
