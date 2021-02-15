//
//  AppDelegate.swift
//  Akai
//
//  Created by nicolai92 on 27.07.19.
//  Copyright © 2020 nicolai92. All rights reserved.
//

import Cocoa
import EventKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!

    // Creates a Status Item in the menu bar with a fixed length
    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    // Status, if permission to access calendars is granted
    var isAccess = false
    // Holds calendars from Apple's calendar app
    var eventStore = EKEventStore()
    // Exchange calendar, holding the relevant events
    var calendar = EKCalendar()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Initialize access to calendars
        _init()

        // Show Skype icon
        if let button = statusItem.button {
            button.image = NSImage(named:NSImage.Name("SkypeIcon"))
            button.action = #selector(_update(_:))
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        exit(0)
    }

    func requestAccessToCalendar() {
        self.eventStore.requestAccess(to: EKEntityType.event, completion: {
            (accessGranted: Bool, error: Error?) in
                if accessGranted == true {
                    print("Access ... ")
                    self.setStatusOfCalendarAccess(status: true)
                    // Initialize application
                    self._init()
                } else {
                    print("Access denied ... ")
                    self.setStatusOfCalendarAccess(status: false)
                }
        })
    }

    // Get Exchange calendar intially
    func fetchExchangeCalendar() -> EKCalendar? {
        // Filter calendars, that have Exchange as it's type
        let exchangeCal = self.eventStore.calendars(for: .event).filter {$0.source.title == "Exchange"}
        if exchangeCal.count > 0 {
            // Match found
            return exchangeCal.last!
        }
        return nil
    }

    func getExchangeCalendar() -> EKCalendar {
        return self.calendar
    }

    func setExchangeCalendar(calendar: EKCalendar) {
        self.calendar = calendar
    }

    func getStatusOfCalendarAccess() -> Bool {
        return self.isAccess
    }

    func setStatusOfCalendarAccess(status: Bool) {
        self.isAccess = status
    }

    func getMeetingLink(event: EKEvent) -> String? {
        // Use filter instead of for-each loops to get meeting URL
        let links = event.notes?.getURLs()
        if links != nil {
            // Build Skype link if available
            let meetingURL = links!.filter{ $0.isSkypeMeeting() || $0.isMicrosoftTeamsMeeting() }
            if meetingURL.first != nil && meetingURL.first!.isSkypeMeeting() {
                let meetingURL = "lync://confjoin?url=" + (links?.first!.absoluteString)!
                return meetingURL
            }
            else if meetingURL.first != nil && meetingURL.first!.isMicrosoftTeamsMeeting() {
                let meetingURL = links?.first?.absoluteString;
                return meetingURL
            }
        }
        // No Skype link found
        return nil
    }

    func getEvents() -> [EKEvent]? {
        let cal = getExchangeCalendar()

        // Get start and end time of current day to filter for events
        let startDate = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: Date())!
        let endDate = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date())!

        // Match events by start and end time
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [cal])

        return eventStore.events(matching: predicate)
    }

    func getMenu(events: [EKEvent]) -> NSMenu {
        let menu = NSMenu()

        // Show only hour and minute of event in menu item
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"

        // Construct menu by looping over the events
        for event in events {
            // Construct e.g. 10:00 - 11:00 format of event time
            var eventTime = dateFormatter.string(from: event.startDate) + " - " + dateFormatter.string(from: event.endDate)
            // Add identifier, if it is an event of a series of events
            if event.hasRecurrenceRules {
                eventTime = eventTime + " ↺"
            }
            menu.addItem(NSMenuItem(title: eventTime, action: nil, keyEquivalent: ""))

            var item = NSMenuItem()
            // Check, if action needs to be set (if Skype meeting available)
            let meetingLink = getMeetingLink(event: event)
            if meetingLink != nil {
                // If meeting is past due, strike through the meeting title
                if (isPastDue(event: event.endDate)) {
                    item = NSMenuItem(title: event.title, action: #selector(_openLink(_:)), keyEquivalent: "")
                    item.attributedTitle = event.title.strikeThrough()
                    item.representedObject = meetingLink
                }
                else {
                    item = NSMenuItem(title: event.title, action: #selector(_openLink(_:)), keyEquivalent: "")
                    item.attributedTitle = event.title.strikeThrough()
                }
            }
            else {
                // Construct title and space
                item = NSMenuItem(title: event.title!, action: nil, keyEquivalent: "")
            }
            // Add item
            menu.addItem(item)
            // Check, if meeting has a location and is not a Skype location
            if event.location != nil && meetingLink == nil {
                menu.addItem(NSMenuItem(title: event.location!, action: nil, keyEquivalent: ""))
            }
            if event.hasAttendees {
                let count = event.attendees!.count
                var attendees = ""
                attendees = count > 1 ? String(count) + " Attendees" : String(count) + " Attendee"
                menu.addItem(NSMenuItem(title: attendees, action: nil, keyEquivalent: ""))
            }

            // Add seperator
            menu.addItem(NSMenuItem.separator())
        }

        // Add option to quit the application
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(_exit(_:)), keyEquivalent: ""))

        return menu
    }
    
    /*
        Check, whether meeting is in past
     */
    func isPastDue(event:Date) -> Bool {
        return Date() > event ? true : false
    }

    /*
        Application's main entry point
    */
    func _init() {
        // Application can access calendar
        if (getStatusOfCalendarAccess()) {
            // Get Exchange calendar
            let cal = fetchExchangeCalendar()
            if (cal != nil) {
                // Save, because Exchange calendar is fetched only once
                // at the initialization of the application
                setExchangeCalendar(calendar: cal!)
            }
        }
        // Ask for access and let requestAccessToCalendar call run()
        // again on success
        else {
            requestAccessToCalendar()
        }
    }

    @objc func _update(_ sender: Any?) {
        // Use Exchange calendar as source and update menu
        let events = getEvents()!
        let menu = getMenu(events: events)

        // Show updated menu
        self.statusItem.menu = menu
        self.statusItem.popUpMenu(menu)
        // Critical, as otherwise the click action will not be called again
        self.statusItem.menu = nil
    }

    @objc func _openLink(_ sender: Any?) {
        //NSWorkspace.sharedWorkspace().openURL(url))
        let item = sender as! NSMenuItem
        let urlString = item.representedObject as! String
        let url = URL(string: urlString)!
        // Launch Skype with Link
        NSWorkspace.shared.open(url)
    }

    @objc func _exit(_ sender: Any?) {
        exit(0)
    }
}

extension String {
    func getURLs() -> [URL] {
        var urls : [URL] = []
        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            detector.enumerateMatches(in: self, options: [], range: NSMakeRange(0, self.count), using: { (result, _, _) in
                if let match = result, let url = match.url {
                    urls.append(url)
                }
            })
        } catch let error as NSError {
            print(error.localizedDescription)
        }
        return urls
    }
    
    func strikeThrough() -> NSAttributedString {
        let attributeString =  NSMutableAttributedString(string: self)
        attributeString.addAttribute(
            NSAttributedString.Key.strikethroughStyle,
               value: NSUnderlineStyle.single.rawValue,
                   range:NSMakeRange(0,attributeString.length))
        return attributeString
    }
}

extension Date {
    // Convert UTC (or GMT) to local time
    func toLocalTime() -> Date {
        let timezone = TimeZone.current
        let seconds = TimeInterval(timezone.secondsFromGMT(for: self))
        return Date(timeInterval: seconds, since: self)
    }
}

extension URL {
    func isSkypeMeeting() -> Bool {
        // Check for Skype link / Skip Skype Web App link
        return self.absoluteString.range(of: "https://meet.") != nil && self.absoluteString.range(of: "sl=1") == nil ? true : false
    }
    
    func isMicrosoftTeamsMeeting() -> Bool {
        // Check for Microsoft Teams link
        return self.absoluteString.range(of: "https://teams.") != nil ? true : false
    }
    
    func isZoomMeeting() -> Bool {
        // Check for Zoom link
        return self.absoluteString.range(of: ".zoom.us") != nil ? true : false
    }
}
