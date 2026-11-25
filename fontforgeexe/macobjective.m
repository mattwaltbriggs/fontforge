/* Copyright (C) 2000-2012 by George Williams */
/* Copyright (C) 2021 by Jeremy Tan */
/*
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this
 * list of conditions and the following disclaimer.

 * Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.

 * The name of the author may not be used to endorse or promote products
 * derived from this software without specific prior written permission.

 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

//  clang-format -i --style=Webkit fontforgeexe/macobjective.m

#include <fontforge-config.h>

#import <Cocoa/Cocoa.h>

#pragma push_macro("AnchorPoint")
#pragma push_macro("FontInfo")
#pragma push_macro("KernPair")
#define AnchorPoint FFAnchorPoint
#define FontInfo FFFontInfo
#define KernPair FFKernPair
#include "fontforgeui.h"
#pragma pop_macro("KernPair")
#pragma pop_macro("FontInfo")
#pragma pop_macro("AnchorPoint")

@interface FFApplication : NSApplication
- (void)registerEventHandlers;
- (bool)setReady;
- (void)handleOpenApplicationEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent;
- (void)handleOpenDocumentsEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent;
- (void)handlePreferencesEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent;
@end

@implementation FFApplication {
    bool ready;
    NSMutableArray* pendingFiles;
}

- (void)registerEventHandlers
{
    // Keep the classic kAEShowPreferences AppleEvent working so Finder and
    // AppleScript can open the FontForge preferences dialog.
    NSAppleEventManager* eventManager = [NSAppleEventManager sharedAppleEventManager];
    [eventManager setEventHandler:self
                      andSelector:@selector
                      (handleOpenApplicationEvent:
                                   withReplyEvent:)
                    forEventClass:kCoreEventClass
                       andEventID:kAEOpenApplication];
    [eventManager setEventHandler:self
                      andSelector:@selector
                      (handleOpenApplicationEvent:
                                   withReplyEvent:)
                    forEventClass:kCoreEventClass
                       andEventID:kAEReopenApplication];
    [eventManager setEventHandler:self
                      andSelector:@selector
                      (handleOpenDocumentsEvent:
                                 withReplyEvent:)
                    forEventClass:kCoreEventClass
                       andEventID:kAEOpenDocuments];
    [eventManager setEventHandler:self
                      andSelector:@selector
                      (handleOpenDocumentsEvent:
                                 withReplyEvent:)
                    forEventClass:kCoreEventClass
                       andEventID:kAEOpenContents];
    [eventManager setEventHandler:self
                      andSelector:@selector
                      (handleQuitEvent:
                          withReplyEvent:)
                    forEventClass:kCoreEventClass
                       andEventID:kAEQuitApplication];
    [eventManager setEventHandler:self
                      andSelector:@selector
                      (handlePreferencesEvent:
                          withReplyEvent:)
                    forEventClass:kCoreEventClass
                       andEventID:kAEShowPreferences];
}

- (bool)setReady
{
    self->ready = true;
    if (self->pendingFiles) {
        [NSApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        for (NSURL* fileUrl in self->pendingFiles) {
            ViewPostScriptFont([fileUrl fileSystemRepresentation], 0);
        }
        [self->pendingFiles release];
        self->pendingFiles = nil;
        return true;
    }
    return false;
}

- (void)handleOpenApplicationEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent
{
    if (self->ready && fv_list == NULL) {
        [NSApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        _FVMenuOpen(NULL);
    }
}

- (void)handleOpenDocumentsEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent
{
    NSAppleEventDescriptor* files = [event paramDescriptorForKeyword:keyDirectObject];
    if (!files) {
        return;
    }

    for (NSInteger i = 1; i <= [files numberOfItems]; ++i) {
        NSString* fileUrlStr = [[files descriptorAtIndex:i] stringValue];
        if (!fileUrlStr) {
            continue;
        }

        // Opening a document from Finder usually delivers a path, while drag
        // and drop may deliver a file:// URL. Accept both forms.
        NSURL* fileUrl = [NSURL URLWithString:fileUrlStr];
        if (!fileUrl || ![fileUrl isFileURL]) {
            fileUrl = [NSURL fileURLWithPath:fileUrlStr];
        }
        if (!fileUrl) {
            continue;
        }

        // GDK also pumps the event loop before we're ready, which means
        // that this event may fire before we can actually process it.
        // So store the files to open until we're ready.
        if (!self->ready) {
            if (!self->pendingFiles) {
                self->pendingFiles = [[NSMutableArray alloc] init];
            }
            [self->pendingFiles addObject:fileUrl];
            continue;
        }

        [NSApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        ViewPostScriptFont([fileUrl fileSystemRepresentation], 0);
    }
}

- (void)handlePreferencesEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent
{
    if (self->ready) {
        [NSApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        MenuPrefs(NULL, NULL, NULL);
    }
}

- (void)handleQuitEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent
{
    if (self->ready) {
        MenuExit(NULL, NULL, NULL);
    }
}

@end

void setup_cocoa_app(void)
{
    [[FFApplication sharedApplication] registerEventHandlers];

    // launchd (pid=1) sets the cwd to the root folder, so change it to home
    // https://stackoverflow.com/a/52688733
    if (getppid() == 1 && getenv("HOME") != NULL) {
        chdir(getenv("HOME"));
    }
}

bool launch_cocoa_app(void)
{
    return [[FFApplication sharedApplication] setReady];
}