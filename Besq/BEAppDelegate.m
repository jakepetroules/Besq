/*
 * Copyright (c) 2013 Petroules Corporation. All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "BEAppDelegate.h"

@implementation BEAppDelegate

/*!
 * Returns an image with an alpha channel added if not is not present,
 * and with transparent pixels trimmed from the edges.
 */
+ (NSImage *)imageByProcessingImage:(NSImage *)image withSquareTargetSize:(NSInteger)size
{
    CGImageRef cgImage = [image CGImageForProposedRect:nil context:nil hints:nil];
    const CGRect cgImageRect = CGRectMake(0, 0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));

    // The rectangle to crop out, if we end up having to trim transparent pixels
    CGRect cropRect = cgImageRect;

    // Create an offscreen context and draw the image into it
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    CGContextRef offscreenContext = CGBitmapContextCreate(NULL, CGRectGetWidth(cgImageRect), CGRectGetHeight(cgImageRect), 8, 0, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(offscreenContext, cgImageRect, cgImage);

    // Only need to trim transparent pixels if the original image actually had an alpha channel
    if (CGImageGetAlphaInfo(cgImage) != kCGImageAlphaNone)
    {
        unsigned char *data = CGBitmapContextGetData(offscreenContext);
        if (data)
        {
            CGSize size = cgImageRect.size;
            CGPoint low = CGPointMake(CGRectGetWidth(cgImageRect), CGRectGetHeight(cgImageRect));
            CGPoint high = CGPointZero;

            for (NSInteger y = 0; y < (NSInteger)size.height; ++y)
            {
                for (NSInteger x = 0; x < (NSInteger)size.width; ++x)
                {
                    if (data[(((NSInteger)size.width * y) + x) * 4] != 0)
                    {
                        if (x < (NSInteger)low.x)
                            low.x = x;
                        if (x > (NSInteger)high.x)
                            high.x = x;
                        if (y < (NSInteger)low.y)
                            low.y = y;
                        if (y > (NSInteger)high.y)
                            high.y = y;
                    }
                }
            }

            cropRect = CGRectMake(low.x, low.y, high.x - low.x, high.y - low.y);
        }
    }

    // Get an image back out of this
    CGImageRef alphaImage = CGBitmapContextCreateImage(offscreenContext);
    CGContextRelease(offscreenContext);

    // Crop the image, if necessary
    CGImageRef croppedImage = CGRectEqualToRect(cgImageRect, cropRect) ? 0 : CGImageCreateWithImageInRect(alphaImage, cropRect);
    CGImageRelease(alphaImage);

    // Find the maximum size of the image that will fit within a {size}x{size} square image
    const CGSize croppedSize = cropRect.size;
    CGRect resampledBounds = CGRectMake(0, 0, size, size);
    if (croppedSize.width > croppedSize.height)
    {
        resampledBounds.size.height = (size / croppedSize.width) * croppedSize.height;
        resampledBounds.origin.y = (size - resampledBounds.size.height) / 2;
    }
    else if (croppedSize.height > croppedSize.width)
    {
        resampledBounds.size.width = (size / croppedSize.height) * croppedSize.width;
        resampledBounds.origin.x = (size - resampledBounds.size.width) / 2;
    }

    // Resample the image to the final target size
    offscreenContext = CGBitmapContextCreate(NULL, size, size, 8, 0, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);
    CGContextDrawImage(offscreenContext, resampledBounds, croppedImage);
    CGImageRelease(croppedImage);

    // Get an image back out of this
    CGImageRef finalImage = CGBitmapContextCreateImage(offscreenContext);
    CGContextRelease(offscreenContext);

    NSImage *newImage = [[NSImage alloc] initWithCGImage:finalImage size:NSZeroSize];
    CGImageRelease(finalImage);
    return newImage;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self.window registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
    [self.window makeFirstResponder:nil];

    if (NSClassFromString(@"NSUserNotificationCenter"))
        [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    [self.progressIndicator stopAnimation:nil];

    NSImage *image = [[NSImage alloc] initByReferencingFile:filename];
    if (!image)
        return NO;

    [self.progressIndicator startAnimation:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Block for error handling
        __block NSError *error = nil;
        dispatch_block_t errorPresentationBlock = ^{
            [self.window makeKeyAndOrderFront:nil];
            [self.window makeFirstResponder:nil];
            [self.progressIndicator stopAnimation:nil];
            [NSApp presentError:error];
        };

        // Load the image from disk and check for validity
        if (![image isValid])
        {
            error = [NSError errorWithDomain:NSCocoaErrorDomain code:0 userInfo:
                     [NSDictionary dictionaryWithObjectsAndKeys:NSLocalizedString(@"The image was not valid", nil), NSLocalizedDescriptionKey, nil]];
            dispatch_async(dispatch_get_main_queue(), errorPresentationBlock);
            return;
        }

        // "Process" the image, that is, add an alpha channel if one is not present, and trim transparent pixels from the edges
        NSImage *processedImage = [[self class] imageByProcessingImage:image withSquareTargetSize:self.imageSizeTextField.integerValue];
        NSData *imageData = [[NSBitmapImageRep imageRepWithData:[processedImage TIFFRepresentation]] representationUsingType:NSPNGFileType properties:nil];
        NSString *newFileName = [[filename stringByDeletingPathExtension] stringByAppendingPathExtension:@"png"];

        // Write the processed image to disk, removing the original in the process
        if (![filename isEqualToString:newFileName])
        {
            [[NSFileManager defaultManager] removeItemAtPath:filename error:&error];
            if (error)
            {
                dispatch_async(dispatch_get_main_queue(), errorPresentationBlock);
                return;
            }
        }

        [imageData writeToFile:newFileName options:NSDataWritingAtomic error:&error];
        if (error)
        {
            dispatch_async(dispatch_get_main_queue(), errorPresentationBlock);
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.progressIndicator stopAnimation:nil];

            if (NSClassFromString(@"NSUserNotificationCenter"))
            {
                NSUserNotification *notification = [[NSUserNotification alloc] init];
                notification.title = NSLocalizedString(@"Conversion Succeeded", nil);
                notification.informativeText = [NSString stringWithFormat:NSLocalizedString(@"The image was successfully resized to %d x %d px and saved as %@", nil), self.imageSizeTextField.intValue, self.imageSizeTextField.intValue, [newFileName lastPathComponent]];
                notification.soundName = NSUserNotificationDefaultSoundName;
                [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
            }
        });
    });

    return YES;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag
{
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:nil];
    return YES;
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
    return YES;
}

@end

@implementation BEWindow

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    if ([[[sender draggingPasteboard] types] containsObject:NSFilenamesPboardType])
        return NSDragOperationCopy;

    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    if ([[[sender draggingPasteboard] types] containsObject:NSFilenamesPboardType])
    {
        NSArray *files = [[sender draggingPasteboard] propertyListForType:NSFilenamesPboardType];
        for (NSString *fileName in files)
            [[NSApp delegate] application:nil openFile:fileName];

        return YES;
    }

    return NO;
}

@end
