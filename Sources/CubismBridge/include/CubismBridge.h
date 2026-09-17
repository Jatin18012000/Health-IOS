#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

/// A loaded Cubism model, wrapped so Swift never sees C++.
///
/// The Cubism SDK for Native is C++. Swift cannot import C++ directly, so this
/// header is deliberately plain Objective-C — no C++ types cross it, which is
/// what lets `AURACharacter` import the module at all. Everything C++ lives in
/// `CubismBridge.mm`.
///
/// The surface is exactly what `Live2DRenderer` drives and nothing more. It is
/// not a general-purpose Cubism wrapper, and it should not grow into one: the
/// renderer sets parameters, ticks physics and draws, and every feature beyond
/// that is one more thing to keep working.
@interface CubismModelHandle : NSObject

/// Load the model in `directory`.
///
/// The directory must contain exactly one `.model3.json`; its references are
/// resolved relative to that file. Returns nil rather than raising if anything
/// is missing, unreadable, or built for a newer Core than this SDK — the
/// character is the least critical thing on screen and must never be the reason
/// the dashboard fails to draw.
- (nullable instancetype)initWithDirectory:(NSString *)directory
    NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/// Why the load failed, when it did. For the placeholder's honest message.
@property(nonatomic, readonly, copy, nullable) NSString *failureReason;

/// Parameter IDs the loaded rig actually has.
///
/// Lets a caller check a rig against what it intends to drive rather than
/// setting a parameter into the void — an ID that does not exist is silently
/// ignored by Cubism, which is the hardest kind of rigging bug to notice.
@property(nonatomic, readonly, copy) NSArray<NSString *> *parameterIds;

/// Set one parameter. Unknown IDs are ignored, as Cubism does.
- (void)setParameter:(NSString *)name value:(float)value;

/// Commit this frame's parameter values to the model.
- (void)update;

/// Advance hair physics by `deltaTime` seconds.
///
/// Reads the parameters set this frame and produces the hair movement, so it
/// must run after `setParameter` and before `update`.
- (void)updatePhysics:(float)deltaTime;

/// Build the Metal renderer. Call once, before the first draw.
- (BOOL)prepareRendererWithDevice:(id<MTLDevice>)device
                     drawableSize:(CGSize)size;

/// The drawable changed size; recompute the projection.
- (void)setDrawableSize:(CGSize)size;

/// Draw into the pass. Encoding is the renderer's; the caller owns present.
- (void)drawWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
         renderPassDescriptor:(MTLRenderPassDescriptor *)descriptor;

/// The Core version this build links, for diagnostics.
+ (NSString *)coreVersion;

/// The highest `.moc3` format this Core can load.
///
/// The rig in this project is moc3 version 6, which needs a Cubism 5.3 Core.
/// An older one refuses it with a message that does not mention SDK versions,
/// so it is worth being able to print this next to it.
+ (NSInteger)latestSupportedMocVersion;

@end

NS_ASSUME_NONNULL_END
