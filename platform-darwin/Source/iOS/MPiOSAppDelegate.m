//==============================================================================
// This file is part of Master Password.
// Copyright (c) 2011-2017, Maarten Billemont.
//
// Master Password is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Master Password is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You can find a copy of the GNU General Public License in the
// LICENSE file.  Alternatively, see <http://www.gnu.org/licenses/>.
//==============================================================================

#import "MPiOSAppDelegate.h"
#import "MPAppDelegate_Key.h"
#import "MPAppDelegate_Store.h"
#import "MPStoreViewController.h"
#import "mpw-marshal.h"

@interface MPiOSAppDelegate()<UIDocumentInteractionControllerDelegate>

@property(nonatomic, strong) UIDocumentInteractionController *interactionController;
@property(nonatomic, strong) PearlHangDetector *hangDetector;

@end

@implementation MPiOSAppDelegate

+ (void)initialize {

    static dispatch_once_t once = 0;
    dispatch_once( &once, ^{
        [PearlLogger get].historyLevel = [[MPiOSConfig get].traceMode boolValue]? PearlLogLevelTrace: PearlLogLevelInfo;
#ifdef DEBUG
        [PearlLogger get].printLevel = PearlLogLevelTrace;
#else
        [PearlLogger get].printLevel = [[MPiOSConfig get].traceMode boolValue]? PearlLogLevelDebug: PearlLogLevelInfo;
#endif
    } );
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    @try {
//        [[NSBundle mainBundle] mutableInfoDictionary][@"CFBundleDisplayName"] = @"Master Password";
//        [[NSBundle mainBundle] mutableLocalizedInfoDictionary][@"CFBundleDisplayName"] = @"Master Password";

#ifdef CRASHLYTICS
        NSString *crashlyticsAPIKey = [self crashlyticsAPIKey];
        if ([crashlyticsAPIKey length]) {
            inf( @"Initializing Crashlytics" );
#if DEBUG
            [Crashlytics sharedInstance].debugMode = YES;
#endif
            [[Crashlytics sharedInstance] setUserIdentifier:[PearlKeyChain deviceIdentifier]];
            [[Crashlytics sharedInstance] setObjectValue:[PearlKeyChain deviceIdentifier] forKey:@"deviceIdentifier"];
            [[Crashlytics sharedInstance] setUserName:@"Anonymous"];
            [Crashlytics startWithAPIKey:crashlyticsAPIKey];
            [[PearlLogger get] registerListener:^BOOL(PearlLogMessage *message) {
                PearlLogLevel level = PearlLogLevelWarn;
                if ([[MPConfig get].sendInfo boolValue])
                    level = PearlLogLevelDebug;

                if (message.level >= level)
                    CLSLog( @"%@", [message messageDescription] );

                return YES;
            }];
            CLSLog( @"Crashlytics (%@) initialized for: %@ v%@.", //
                    [Crashlytics sharedInstance].version, [PearlInfoPlist get].CFBundleName, [PearlInfoPlist get].CFBundleVersion );
        }
#endif

        [self.hangDetector = [[PearlHangDetector alloc] initWithHangAction:^(NSTimeInterval hangTime) {
            MPError( [NSError errorWithDomain:MPErrorDomain code:MPErrorHangCode userInfo:@{
                    @"time": @(hangTime)
            }], @"Timeout waiting for main thread after %fs.", hangTime );
        }] start];
    }
    @catch (id exception) {
        err( @"During Analytics Setup: %@", exception );
    }
    @try {
        PearlAddNotificationObserver( MPCheckConfigNotification, nil, [NSOperationQueue mainQueue], ^(id self, NSNotification *note) {
            [self updateConfigKey:note.object];
        } );
        PearlAddNotificationObserver( NSUserDefaultsDidChangeNotification, nil, nil, ^(id self, NSNotification *note) {
            [[NSNotificationCenter defaultCenter] postNotificationName:MPCheckConfigNotification object:nil];
        } );
    }
    @catch (id exception) {
        err( @"During Config Test: %@", exception );
    }
    @try {
        [super application:application didFinishLaunchingWithOptions:launchOptions];
    }
    @catch (id exception) {
        err( @"During Pearl Application Launch: %@", exception );
    }
    @try {
        inf( @"Started up with device identifier: %@", [PearlKeyChain deviceIdentifier] );

        PearlAddNotificationObserver( MPFoundInconsistenciesNotification, nil, nil, ^(id self, NSNotification *note) {
            switch ((MPFixableResult)[note.userInfo[MPInconsistenciesFixResultUserKey] unsignedIntegerValue]) {

                case MPFixableResultNoProblems:
                    break;
                case MPFixableResultProblemsFixed: {
                    UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Inconsistencies Fixed" message:
                                    @"Some inconsistencies were detected in your sites.\n"
                                    @"All issues were fixed."
                                                                                 preferredStyle:UIAlertControllerStyleAlert];
                    [controller addAction:[UIAlertAction actionWithTitle:@"Okay" style:UIAlertActionStyleCancel handler:nil]];
                    [self presentViewController:controller animated:YES completion:nil];
                    break;
                }
                case MPFixableResultProblemsNotFixed: {
                    UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Inconsistencies Found" message:
                                    @"Some inconsistencies were detected in your sites.\n"
                                    @"Not all issues could be fixed.  Try signing in to each user or checking the logs."
                                                                                 preferredStyle:UIAlertControllerStyleAlert];
                    [controller addAction:[UIAlertAction actionWithTitle:@"Okay" style:UIAlertActionStyleCancel handler:nil]];
                    [self presentViewController:controller animated:YES completion:nil];
                    break;
                }
            }
        } );

        PearlMainQueue( ^{
            if ([[MPiOSConfig get].showSetup boolValue])
                [self.navigationController performSegueWithIdentifier:@"setup" sender:self];
        } );

        NSString *latestFeatures = [MPStoreViewController latestStoreFeatures];
        if (latestFeatures) {
            UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"New Features" message:
                            strf( @"The following features are now available in the store:\n\n%@•••\n\n"
                                  @"Find the store from the user pull‑down after logging in.", latestFeatures )
                                                                         preferredStyle:UIAlertControllerStyleAlert];
            [controller addAction:[UIAlertAction actionWithTitle:@"Thanks" style:UIAlertActionStyleCancel handler:nil]];
            [self.navigationController presentViewController:controller animated:YES completion:nil];
        }
    }
    @catch (id exception) {
        err( @"During Post-Startup: %@", exception );
    }

    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {

    // No URL?
    if (!url)
        return NO;

    // Arbitrary URL to mpsites data.
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:
            ^(NSData *importedSitesData, NSURLResponse *response, NSError *error) {
                if (error)
                    MPError( error, @"While reading imported sites from %@.", url );

                if (!importedSitesData) {
                    UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Error" message:
                                    strf( @"Master Password couldn't read the import sites.\n\n%@",
                                            (id)[error localizedDescription]?: error )
                                                                                 preferredStyle:UIAlertControllerStyleAlert];
                    [controller addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleCancel handler:nil]];
                    [self.navigationController presentViewController:controller animated:YES completion:nil];
                    return;
                }

                NSString *importedSitesString = [[NSString alloc] initWithData:importedSitesData encoding:NSUTF8StringEncoding];
                if (!importedSitesString) {
                    UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Error" message:
                                    @"Master Password couldn't understand the import file."
                                                                                 preferredStyle:UIAlertControllerStyleAlert];
                    [controller addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleCancel handler:nil]];
                    [self.navigationController presentViewController:controller animated:YES completion:nil];
                    return;
                }

                [self importSites:importedSitesString];
            }] resume];

    return YES;
}

- (void)importSites:(NSString *)importData {

    if ([NSThread isMainThread]) {
        PearlNotMainQueue( ^{
            [self importSites:importData];
        } );
        return;
    }

    PearlOverlay *activityOverlay = [PearlOverlay showProgressOverlayWithTitle:@"Importing"];
    [self importSites:importData askImportPassword:^NSString *(NSString *userName) {
        return PearlAwait( ^(void (^setResult)(id)) {
            UIAlertController *controller = [UIAlertController alertControllerWithTitle:strf( @"Importing Sites For\n%@", userName ) message:
                            @"Enter the master password used to create this export file."
                                                                         preferredStyle:UIAlertControllerStyleAlert];
            [controller addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.secureTextEntry = YES;
            }];
            [controller addAction:[UIAlertAction actionWithTitle:@"Import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                setResult( controller.textFields.firstObject.text );
            }]];
            [controller addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                setResult( nil );
            }]];
            [self.navigationController presentViewController:controller animated:YES completion:nil];
        } );
    } askUserPassword:^NSString *(NSString *userName) {
        return PearlAwait( (id)^(void (^setResult)(id)) {
            UIAlertController *controller = [UIAlertController alertControllerWithTitle:strf( @"Master Password For\n%@", userName ) message:
                            @"Enter the current master password for this user."
                                                                         preferredStyle:UIAlertControllerStyleAlert];
            [controller addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.secureTextEntry = YES;
            }];
            [controller addAction:[UIAlertAction actionWithTitle:@"Import" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                setResult( controller.textFields.firstObject.text );
            }]];
            [controller addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                setResult( nil );
            }]];
            [self.navigationController presentViewController:controller animated:YES completion:nil];
        } );
    }          result:^(NSError *error) {
        [activityOverlay cancelOverlayAnimated:YES];

        if (error && !(error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError)) {
            UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Error" message:[error localizedDescription]
                                                                         preferredStyle:UIAlertControllerStyleAlert];
            [controller addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleCancel handler:nil]];
            [self.navigationController presentViewController:controller animated:YES completion:nil];
        }
    }];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {

    inf( @"Will foreground" );

    [super applicationWillEnterForeground:application];

    [self.hangDetector start];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {

    inf( @"Re-activated" );
    [[NSNotificationCenter defaultCenter] postNotificationName:MPCheckConfigNotification object:nil];

    PearlNotMainQueue( ^{
        NSString *importData = [UIPasteboard generalPasteboard].string;
        MPMarshalInfo *importInfo = mpw_marshal_read_info( importData.UTF8String );
        if (importInfo->format != MPMarshalFormatNone) {
            UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Import Sites?" message:
                            @"We've detected Master Password import sites on your pasteboard, would you like to import them?"
                                                                         preferredStyle:UIAlertControllerStyleAlert];
            [controller addAction:[UIAlertAction actionWithTitle:@"Import Sites" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self importSites:importData];
                [UIPasteboard generalPasteboard].string = @"";
            }]];
            [controller addAction:[UIAlertAction actionWithTitle:@"No" style:UIAlertActionStyleCancel handler:nil]];
            [self.navigationController presentViewController:controller animated:YES completion:nil];
        }
        mpw_marshal_info_free( &importInfo );
    } );

    [super applicationDidBecomeActive:application];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {

    inf( @"Received memory warning." );

    [super applicationDidReceiveMemoryWarning:application];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {

    inf( @"Did background" );
    if (![[MPiOSConfig get].rememberLogin boolValue])
        [self signOutAnimated:NO];

    [self.hangDetector stop];

//    self.task = [application beginBackgroundTaskWithExpirationHandler:^{
//        [application endBackgroundTask:self.task];
//        dbg( @"background expiring" );
//    }];
//    PearlNotMainQueueOperation( ^{
//        NSString *pbstring = [UIPasteboard generalPasteboard].string;
//        while (YES) {
//            NSString *newString = [UIPasteboard generalPasteboard].string;
//            if (![newString isEqualToString:pbstring]) {
//                dbg( @"pasteboard changed to: %@", newString );
//                pbstring = newString;
//                NSURL *url = [NSURL URLWithString:pbstring];
//                if (url) {
//                    NSString *siteName = [url host];
//                }
//                MPKey *key = [MPiOSAppDelegate get].key;
//                if (key)
//                    [MPiOSAppDelegate managedObjectContextPerformBlock:^(NSManagedObjectContext *context) {
//                        NSFetchRequest<MPSiteEntity *>
//                                *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:NSStringFromClass( [MPSiteEntity class] )];
//                        fetchRequest.sortDescriptors = @[
//                                [[NSSortDescriptor alloc] initWithKey:NSStringFromSelector( @selector( lastUsed ) ) ascending:NO]
//                        ];
//                        fetchRequest.fetchBatchSize = 2;
//                        fetchRequest.predicate = [NSPredicate predicateWithFormat:@"(name LIKE[cd] %@) AND user == %@", siteName,
//                                                                                  [[MPiOSAppDelegate get] activeUserOID]];
//                        NSError *error = nil;
//                        NSArray<MPSiteEntity *> *results = [fetchRequest execute:&error];
//                        dbg( @"site search, error: %@, results:\n%@", error, results );
//                        if ([results count]) {
//                            [UIPasteboard generalPasteboard].string = [[results firstObject] resolvePasswordUsingKey:key];
//                        }
//                    }];
//            }
//            [NSThread sleepForTimeInterval:5];
//        }
//    } );

    [super applicationDidEnterBackground:application];
}

#pragma mark - Behavior

- (void)showFeedbackWithLogs:(BOOL)logs forVC:(UIViewController *)viewController {

    if (![PearlEMail canSendMail]) {
        UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Feedback" message:
                        @"Have a question, comment, issue or just saying thanks?\n\n"
                        @"We'd love to hear what you think!\n"
                        @"masterpassword@lyndir.com"
                                                                     preferredStyle:UIAlertControllerStyleAlert];
        [controller addAction:[UIAlertAction actionWithTitle:@"Okay" style:UIAlertActionStyleCancel handler:nil]];
        [self.navigationController presentViewController:controller animated:YES completion:nil];
    }
    else if (logs) {
        UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Feedback" message:
                        @"Have a question, comment, issue or just saying thanks?\n\n"
                        @"If you're having trouble, it may help us if you can first reproduce the problem "
                        @"and then include log files in your message."
                                                                     preferredStyle:UIAlertControllerStyleAlert];
        [controller addAction:[UIAlertAction actionWithTitle:@"Include Logs" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self openFeedbackWithLogs:YES forVC:viewController];
        }]];
        [controller addAction:[UIAlertAction actionWithTitle:@"No Logs" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self openFeedbackWithLogs:NO forVC:viewController];
        }]];
        [self.navigationController presentViewController:controller animated:YES completion:nil];
    }
    else
        [self openFeedbackWithLogs:NO forVC:viewController];
}

- (void)openFeedbackWithLogs:(BOOL)logs forVC:(UIViewController *)viewController {

    NSString *userName = [[MPiOSAppDelegate get] activeUserForMainThread].name;
    PearlLogLevel logLevel = PearlLogLevelInfo;
    if (logs && ([[MPConfig get].sendInfo boolValue] || [[MPiOSConfig get].traceMode boolValue]))
        logLevel = PearlLogLevelDebug;

    [[[PearlEMail alloc] initForEMailTo:@"Master Password Development <masterpassword@lyndir.com>"
                                subject:strf( @"Feedback for Master Password [%@]",
                                        [[PearlKeyChain deviceIdentifier] stringByDeletingMatchesOf:@"-.*"] )
                                   body:strf( @"\n\n\n"
                                              @"--\n"
                                              @"%@"
                                              @"Master Password %@, build %@",
                                           userName? ([userName stringByAppendingString:@"\n"]): @"",
                                           [PearlInfoPlist get].CFBundleShortVersionString,
                                           [PearlInfoPlist get].CFBundleVersion )

                            attachments:(logs
                                         ? [[PearlEMailAttachment alloc]
                                                 initWithContent:[[[PearlLogger get] formatMessagesWithLevel:logLevel]
                                                         dataUsingEncoding:NSUTF8StringEncoding]
                                                        mimeType:@"text/plain"
                                                        fileName:strf( @"%@-%@.log",
                                                                [[NSDateFormatter rfc3339DateFormatter] stringFromDate:[NSDate date]],
                                                                [PearlKeyChain deviceIdentifier] )]
                                         : nil), nil]
            showComposerForVC:viewController];
}

- (void)handleCoordinatorError:(NSError *)error {

    static dispatch_once_t once = 0;
    dispatch_once( &once, ^{
        UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Failed To Load Sites" message:
                        @"Master Password was unable to open your sites history.\n"
                        @"This may be due to corruption.  You can either reset Master Password and "
                        @"recreate your user, or E-Mail us your logs and leave your corrupt store as-is for now."
                                                                     preferredStyle:UIAlertControllerStyleAlert];
        [controller addAction:[UIAlertAction actionWithTitle:@"E-Mail Logs" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self openFeedbackWithLogs:YES forVC:nil];
        }]];
        [controller addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self deleteAndResetStore];
        }]];
        [controller addAction:[UIAlertAction actionWithTitle:@"Ignore" style:UIAlertActionStyleCancel handler:nil]];
        [self.navigationController presentViewController:controller animated:YES completion:nil];
    } );
}

- (void)showExportForVC:(UIViewController *)viewController {

    UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Exporting Your Sites" message:
                    @"An export is great for keeping a backup list of your accounts.\n\n"
                    @"When the file is ready, you will be able to mail it to yourself.\n"
                    @"You can open it with a text editor or with Master Password if you need to restore your list of sites."
                                                                 preferredStyle:UIAlertControllerStyleAlert];
    [controller addAction:[UIAlertAction actionWithTitle:@"Export Sites" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIAlertController *controller_ = [UIAlertController alertControllerWithTitle:@"Show Passwords?" message:
                        @"Would you like to make all your passwords visible in the export file?\n\n"
                        @"A safe export will include all sites but make their passwords invisible.\n"
                        @"It is great as a backup and remains safe when fallen in the wrong hands."
                                                                      preferredStyle:UIAlertControllerStyleAlert];
        [controller_ addAction:[UIAlertAction actionWithTitle:@"Safe Export" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                 [self showExportRevealPasswords:NO forVC:viewController];
        }]];
        [controller_ addAction:[UIAlertAction actionWithTitle:@"Show Passwords" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                                 [self showExportRevealPasswords:YES forVC:viewController];
        }]];
        [controller_ addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self.navigationController presentViewController:controller_ animated:YES completion:nil];
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self.navigationController presentViewController:controller animated:YES completion:nil];
}

- (void)showExportRevealPasswords:(BOOL)revealPasswords forVC:(UIViewController *)viewController {

    if (![PearlEMail canSendMail]) {
        UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Cannot Send Mail" message:
                        @"Your device is not yet set up for sending mail.\n"
                        @"Close Master Password, go into Settings and add a Mail account."
                                                                     preferredStyle:UIAlertControllerStyleAlert];
        [controller addAction:[UIAlertAction actionWithTitle:@"Okay" style:UIAlertActionStyleCancel handler:nil]];
        [self.navigationController presentViewController:controller animated:YES completion:nil];
        return;
    }

    [self exportSitesRevealPasswords:revealPasswords askExportPassword:^NSString *(NSString *userName) {
        return PearlAwait( ^(void (^setResult)(id)) {
            UIAlertController *controller = [UIAlertController alertControllerWithTitle:strf( @"Master Password For:\n%@", userName ) message:
                            @"Enter the user's master password to create an export file."
                                                                         preferredStyle:UIAlertControllerStyleAlert];
            [controller addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.secureTextEntry = YES;
            }];
            [controller addAction:[UIAlertAction actionWithTitle:@"Export" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                setResult( controller.textFields.firstObject.text );
            }]];
            [controller addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                setResult( nil );
            }]];
            [self.navigationController presentViewController:controller animated:YES completion:nil];
        } );
    }                         result:^(NSString *mpsites, NSError *error) {
        if (!mpsites || error) {
            MPError( error, @"Failed to export mpsites." );
            UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Export Error" message:[error localizedDescription]
                                                                         preferredStyle:UIAlertControllerStyleAlert];
            [controller addAction:[UIAlertAction actionWithTitle:@"Okay" style:UIAlertActionStyleCancel handler:nil]];
            [self.navigationController presentViewController:controller animated:YES completion:nil];
            return;
        }

        NSDateFormatter *exportDateFormatter = [NSDateFormatter new];
        [exportDateFormatter setDateFormat:@"yyyy'-'MM'-'dd"];
        NSString *exportFileName = strf( @"%@ (%@).mpsites",
                [self activeUserForMainThread].name, [exportDateFormatter stringFromDate:[NSDate date]] );

        UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Export Destination" message:nil
                                                                     preferredStyle:UIAlertControllerStyleActionSheet];
        [controller addAction:[UIAlertAction actionWithTitle:@"Send As E-Mail" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *message;
            if (revealPasswords)
                message = strf( @"Export of Master Password sites with passwords included.\n\n"
                                @"REMINDER: Make sure nobody else sees this file!  Passwords are visible!\n\n\n"
                                @"--\n"
                                @"%@\n"
                                @"Master Password %@, build %@",
                        [self activeUserForMainThread].name,
                        [PearlInfoPlist get].CFBundleShortVersionString,
                        [PearlInfoPlist get].CFBundleVersion );
            else
                message = strf( @"Backup of Master Password sites.\n\n\n"
                                @"--\n"
                                @"%@\n"
                                @"Master Password %@, build %@",
                        [self activeUserForMainThread].name,
                        [PearlInfoPlist get].CFBundleShortVersionString,
                        [PearlInfoPlist get].CFBundleVersion );

            [PearlEMail sendEMailTo:nil fromVC:viewController subject:@"Master Password Export" body:message
                        attachments:[[PearlEMailAttachment alloc]
                                            initWithContent:[mpsites dataUsingEncoding:NSUTF8StringEncoding]
                                                   mimeType:@"text/plain" fileName:exportFileName],
                                    nil];
            return;
        }]];
        [controller addAction:[UIAlertAction actionWithTitle:@"Share / Airdrop" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSURL *applicationSupportURL = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                                                   inDomains:NSUserDomainMask] lastObject];
            NSURL *exportURL = [[applicationSupportURL
                    URLByAppendingPathComponent:[NSBundle mainBundle].bundleIdentifier isDirectory:YES]
                    URLByAppendingPathComponent:exportFileName isDirectory:NO];
            NSError *writeError = nil;
            if (![[mpsites dataUsingEncoding:NSUTF8StringEncoding]
                    writeToURL:exportURL options:NSDataWritingFileProtectionComplete error:&writeError])
                MPError( writeError, @"Failed to write export data to URL %@.", exportURL );
            else {
                self.interactionController = [UIDocumentInteractionController interactionControllerWithURL:exportURL];
                self.interactionController.UTI = @"com.lyndir.masterpassword.sites";
                self.interactionController.delegate = self;
                [self.interactionController presentOpenInMenuFromRect:CGRectZero inView:viewController.view animated:YES];
            }
        }]];
        [controller addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleCancel handler:nil]];
        [self.navigationController presentViewController:controller animated:YES completion:nil];
    }];
}

- (void)changeMasterPasswordFor:(MPUserEntity *)user saveInContext:(NSManagedObjectContext *)moc didResetBlock:(void ( ^ )(void))didReset {

    UIAlertController *controller = [UIAlertController alertControllerWithTitle:@"Changing Master Password" message:
                    @"If you continue, you'll be able to set a new master password.\n\n"
                    @"Changing your master password will cause all your generated passwords to change!\n"
                    @"Changing the master password back to the old one will cause your passwords to revert as well."
                                                                 preferredStyle:UIAlertControllerStyleAlert];
    [controller addAction:[UIAlertAction actionWithTitle:@"Abort" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [moc performBlockAndWait:^{
            inf( @"Clearing keyID for user: %@.", user.userID );
            user.keyID = nil;
            [self forgetSavedKeyFor:user];
            [moc saveToStore];
        }];

        [self signOutAnimated:YES];
        if (didReset)
            didReset();
    }]];
    [controller addAction:[UIAlertAction actionWithTitle:@"Abort" style:UIAlertActionStyleCancel handler:nil]];
    [self.navigationController presentViewController:controller animated:YES completion:nil];
}

#pragma mark - UIDocumentInteractionControllerDelegate

- (void)documentInteractionController:(UIDocumentInteractionController *)controller didEndSendingToApplication:(NSString *)application {

//    self.interactionController = nil;
}

#pragma mark - PearlConfigDelegate

- (void)didUpdateConfigForKey:(SEL)configKey fromValue:(id)value {

    [[NSNotificationCenter defaultCenter] postNotificationName:MPCheckConfigNotification object:NSStringFromSelector( configKey )];
}

- (void)updateConfigKey:(NSString *)key {

    // Trace mode
    [PearlLogger get].historyLevel = [[MPiOSConfig get].traceMode boolValue]? PearlLogLevelTrace: PearlLogLevelInfo;

    // Send info
    if ([[MPConfig get].sendInfo boolValue]) {
        if ([PearlLogger get].printLevel > PearlLogLevelInfo)
            [PearlLogger get].printLevel = PearlLogLevelInfo;

#ifdef CRASHLYTICS
        [[Crashlytics sharedInstance] setBoolValue:[[MPConfig get].rememberLogin boolValue] forKey:@"rememberLogin"];
        [[Crashlytics sharedInstance] setBoolValue:[[MPConfig get].sendInfo boolValue] forKey:@"sendInfo"];
        [[Crashlytics sharedInstance] setBoolValue:[[MPiOSConfig get].helpHidden boolValue] forKey:@"helpHidden"];
        [[Crashlytics sharedInstance] setBoolValue:[[MPiOSConfig get].showSetup boolValue] forKey:@"showQuickStart"];
        [[Crashlytics sharedInstance] setBoolValue:[[PearlConfig get].firstRun boolValue] forKey:@"firstRun"];
        [[Crashlytics sharedInstance] setIntValue:[[PearlConfig get].launchCount intValue] forKey:@"launchCount"];
        [[Crashlytics sharedInstance] setBoolValue:[[PearlConfig get].askForReviews boolValue] forKey:@"askForReviews"];
        [[Crashlytics sharedInstance] setIntValue:[[PearlConfig get].reviewAfterLaunches intValue] forKey:@"reviewAfterLaunches"];
        [[Crashlytics sharedInstance] setObjectValue:[PearlConfig get].reviewedVersion forKey:@"reviewedVersion"];
        [[Crashlytics sharedInstance] setBoolValue:[PearlDeviceUtils isSimulator] forKey:@"simulator"];
        [[Crashlytics sharedInstance] setBoolValue:[PearlDeviceUtils isAppEncrypted] forKey:@"encrypted"];
        [[Crashlytics sharedInstance] setBoolValue:[PearlDeviceUtils isJailbroken] forKey:@"jailbroken"];
        [[Crashlytics sharedInstance] setObjectValue:[PearlDeviceUtils platform] forKey:@"platform"];
#ifdef APPSTORE
        [[Crashlytics sharedInstance] setBoolValue:[PearlDeviceUtils isAppEncrypted] forKey:@"reviewedVersion"];
#else
        [[Crashlytics sharedInstance] setBoolValue:YES forKey:@"reviewedVersion"];
#endif
#endif
    }
}

#pragma mark - Crashlytics

- (NSDictionary *)crashlyticsInfo {

    static NSDictionary *crashlyticsInfo = nil;
    if (crashlyticsInfo == nil)
        crashlyticsInfo = [[NSDictionary alloc] initWithContentsOfURL:
                [[NSBundle mainBundle] URLForResource:@"Fabric" withExtension:@"plist"]];

    return crashlyticsInfo;
}

- (NSString *)crashlyticsAPIKey {

    NSString *crashlyticsAPIKey = NSNullToNil( [[self crashlyticsInfo] valueForKeyPath:@"API Key"] );
    if (![crashlyticsAPIKey length])
        wrn( @"Crashlytics API key not set.  Crash logs won't be recorded." );

    return crashlyticsAPIKey;
}

@end
