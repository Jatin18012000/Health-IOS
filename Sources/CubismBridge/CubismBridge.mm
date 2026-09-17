#import "include/CubismBridge.h"

#import <MetalKit/MetalKit.h>

#include <CubismFramework.hpp>
#include <CubismModelSettingJson.hpp>
#include <Id/CubismIdManager.hpp>
#include <Math/CubismMatrix44.hpp>
#include <Model/CubismUserModel.hpp>
#include <Physics/CubismPhysics.hpp>
#include <Rendering/Metal/CubismRenderer_Metal.hpp>
#include <Type/csmString.hpp>

#include <string>
#include <vector>

using namespace Live2D::Cubism::Framework;
using namespace Live2D::Cubism::Framework::Rendering;

// ────────────────────────────────────────────────────────────────────────────
// UNVERIFIED AGAINST A COMPILER.
//
// There is no Swift toolchain and no Cubism SDK in the environment this was
// written in, so this file has never been built. The call shapes come from the
// published Framework headers (CubismUserModel, CubismModelSettingJson,
// CubismModel, CubismRenderer_Metal), read from Live2D's own repository rather
// than recalled — but reading a header is not compiling against it. Expect the
// first `swift build` on a Mac to produce real errors here.
//
// What is structurally sound and worth preserving through those fixes:
//   - the header stays pure Objective-C, which is what lets Swift import it
//   - the framework is started once and disposed once, process-wide
//   - physics runs between setting parameters and committing them
//   - a load failure degrades to the placeholder instead of crashing
// ────────────────────────────────────────────────────────────────────────────

namespace {

/// Cubism requires an allocator; it does not provide one.
class Allocator : public ICubismAllocator {
    void *Allocate(const csmSizeType size) override { return malloc(size); }
    void Deallocate(void *memory) override { free(memory); }

    /// Aligned allocation done by hand because Cubism hands back the *shifted*
    /// pointer and expects to get it back on release — so the original malloc
    /// pointer is stashed in the bytes immediately before it.
    void *AllocateAligned(const csmSizeType size, const csmUint32 alignment) override {
        const size_t offset = alignment - 1 + sizeof(void *);
        void *const block = malloc(size + offset);
        if (block == nullptr) { return nullptr; }
        void **const aligned = reinterpret_cast<void **>(
            (reinterpret_cast<size_t>(block) + offset) & ~(alignment - 1));
        aligned[-1] = block;
        return aligned;
    }

    void DeallocateAligned(void *alignedMemory) override {
        if (alignedMemory == nullptr) { return; }
        free(static_cast<void **>(alignedMemory)[-1]);
    }
};

Allocator gAllocator;
CubismFramework::Option gOption;
bool gStarted = false;

/// Started once per process and never torn down.
///
/// Cubism's startup is global state, and two models on screen at once would
/// otherwise race it. Nothing in this app ever needs it stopped — the character
/// lives as long as the window does.
bool StartFrameworkOnce() {
    if (gStarted) { return true; }
    gOption.LogFunction = nullptr;
    gOption.LoggingLevel = CubismFramework::Option::LogLevel_Warning;
    if (!CubismFramework::StartUp(&gAllocator, &gOption)) { return false; }
    CubismFramework::Initialize();
    gStarted = true;
    return true;
}

NSData *_Nullable ReadFile(NSString *path) {
    return [NSData dataWithContentsOfFile:path options:0 error:nil];
}

/// The model3.json in a directory, or nil when there is not exactly one.
///
/// Exactly one, not the first: a directory with two entry points is ambiguous,
/// and silently picking one produces a model that is subtly not the one meant.
NSString *_Nullable FindModelJSON(NSString *directory) {
    NSArray<NSString *> *const entries =
        [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil];
    NSMutableArray<NSString *> *const found = [NSMutableArray array];
    for (NSString *entry in entries) {
        if ([entry hasSuffix:@".model3.json"]) { [found addObject:entry]; }
    }
    return found.count == 1 ? [directory stringByAppendingPathComponent:found.firstObject]
                            : nil;
}

/// Subclassed only to reach `_physics` and `_model`, which `CubismUserModel`
/// keeps protected. No behaviour is added.
class AuraModel : public CubismUserModel {
public:
    CubismPhysics *Physics() const { return _physics; }
    CubismModel *Model() const { return _model; }
    CubismModelMatrix *Matrix() const { return _modelMatrix; }
};

}  // namespace

@implementation CubismModelHandle {
    AuraModel *_model;
    CGSize _drawableSize;
    BOOL _rendererReady;
    /// Kept so the renderer can resolve texture paths at prepare time, which
    /// happens later than load and needs the same relative base.
    NSString *_textureDirectory;
    NSString *_settingsPath;
}

- (nullable instancetype)initWithDirectory:(NSString *)directory {
    self = [super init];
    if (self == nil) { return nil; }

    _parameterIds = @[];
    _drawableSize = CGSizeMake(1, 1);

    if (!StartFrameworkOnce()) {
        _failureReason = @"the Cubism framework would not start";
        return nil;
    }

    NSString *const modelJSON = FindModelJSON(directory);
    if (modelJSON == nil) {
        _failureReason = @"expected exactly one .model3.json in the rig folder";
        return nil;
    }

    NSData *const settingsData = ReadFile(modelJSON);
    if (settingsData == nil) {
        _failureReason = @"the .model3.json could not be read";
        return nil;
    }

    CubismModelSettingJson settings(
        static_cast<const csmByte *>(settingsData.bytes),
        static_cast<csmSizeInt>(settingsData.length));

    _model = new AuraModel();

    // The rig itself.
    NSString *const mocName = @(settings.GetModelFileName());
    NSData *const moc = ReadFile([directory stringByAppendingPathComponent:mocName]);
    if (moc == nil || moc.length == 0) {
        _failureReason = [NSString stringWithFormat:@"missing %@", mocName];
        delete _model; _model = nullptr;
        return nil;
    }

    // Checked rather than assumed: a rig newer than this Core fails inside
    // LoadModel with a message that does not say "your SDK is too old".
    const Core::csmMocVersion mocVersion = CubismUserModel::GetMocVersionFromBuffer(
        static_cast<const csmByte *>(moc.bytes), static_cast<csmSizeInt>(moc.length));
    if (mocVersion > Core::csmGetLatestMocVersion()) {
        _failureReason = [NSString stringWithFormat:
            @"this rig is moc3 version %d and the linked Cubism Core only reads "
            @"up to %d — the SDK is too old",
            static_cast<int>(mocVersion),
            static_cast<int>(Core::csmGetLatestMocVersion())];
        delete _model; _model = nullptr;
        return nil;
    }

    _model->LoadModel(static_cast<const csmByte *>(moc.bytes),
                      static_cast<csmSizeInt>(moc.length));

    // Physics is optional to load and very visible when absent: without it the
    // hair turns with the head as one rigid piece.
    const csmChar *const physicsName = settings.GetPhysicsFileName();
    if (physicsName != nullptr && strlen(physicsName) > 0) {
        NSData *const physics =
            ReadFile([directory stringByAppendingPathComponent:@(physicsName)]);
        if (physics != nil) {
            _model->LoadPhysics(static_cast<const csmByte *>(physics.bytes),
                                static_cast<csmSizeInt>(physics.length));
        }
    }

    if (_model->GetModel() == nullptr) {
        _failureReason = @"the rig loaded but produced no model";
        delete _model; _model = nullptr;
        return nil;
    }

    // Read back what the rig actually has, so a caller can check it against
    // what it means to drive.
    NSMutableArray<NSString *> *const ids = [NSMutableArray array];
    CubismModel *const model = _model->GetModel();
    for (csmInt32 i = 0; i < model->GetParameterCount(); i++) {
        [ids addObject:@(model->GetParameterId(i)->GetString().GetRawString())];
    }
    _parameterIds = [ids copy];
    _textureDirectory = [directory copy];
    _settingsPath = [modelJSON copy];

    return self;
}

- (void)dealloc {
    delete _model;
    _model = nullptr;
}

// MARK: - Driving

- (void)setParameter:(NSString *)name value:(float)value {
    if (_model == nullptr) { return; }
    CubismModel *const model = _model->GetModel();
    if (model == nullptr) { return; }
    // Cubism ignores an unknown id rather than failing, which is why
    // `parameterIds` exists — the caller checks, this does not.
    model->SetParameterValue(
        CubismFramework::GetIdManager()->GetId(name.UTF8String), value);
}

- (void)updatePhysics:(float)deltaTime {
    if (_model == nullptr) { return; }
    CubismPhysics *const physics = _model->Physics();
    if (physics == nullptr) { return; }
    physics->Evaluate(_model->GetModel(), deltaTime);
}

- (void)update {
    if (_model == nullptr) { return; }
    CubismModel *const model = _model->GetModel();
    if (model != nullptr) { model->Update(); }
}

// MARK: - Rendering

- (BOOL)prepareRendererWithDevice:(id<MTLDevice>)device
                     drawableSize:(CGSize)size {
    if (_model == nullptr || _rendererReady) { return _rendererReady; }

    _drawableSize = size;

    // Static, and must come before CreateRenderer: the renderer reads the
    // device out of this when it builds its pipeline state.
    CubismRenderer_Metal::SetConstantSettings(device, 1);
    _model->CreateRenderer(static_cast<csmUint32>(size.width),
                           static_cast<csmUint32>(size.height));

    CubismRenderer_Metal *const renderer =
        _model->GetRenderer<CubismRenderer_Metal>();
    if (renderer == nullptr) { return NO; }

    // Textures are named by the model3.json, relative to it.
    NSData *const settingsData = ReadFile(_settingsPath);
    if (settingsData == nil) { return NO; }
    CubismModelSettingJson settings(
        static_cast<const csmByte *>(settingsData.bytes),
        static_cast<csmSizeInt>(settingsData.length));

    MTKTextureLoader *const loader =
        [[MTKTextureLoader alloc] initWithDevice:device];
    for (csmInt32 i = 0; i < settings.GetTextureCount(); i++) {
        NSString *const relative = @(settings.GetTextureFileName(i));
        NSURL *const url = [NSURL fileURLWithPath:
            [_textureDirectory stringByAppendingPathComponent:relative]];
        // Origin flipped: Cubism's texture space is bottom-left, Metal's is
        // top-left. Without this she renders upside down, which reads as a
        // broken rig rather than a coordinate convention.
        id<MTLTexture> const texture =
            [loader newTextureWithContentsOfURL:url
                                        options:@{MTKTextureLoaderOptionOrigin:
                                                      MTKTextureLoaderOriginFlippedVertically}
                                          error:nil];
        if (texture == nil) { return NO; }
        renderer->BindTexture(static_cast<csmUint32>(i), texture);
    }

    renderer->IsPremultipliedAlpha(true);
    _rendererReady = YES;
    return YES;
}

- (void)setDrawableSize:(CGSize)size {
    _drawableSize = size;
}

- (void)drawWithCommandBuffer:(id<MTLCommandBuffer>)commandBuffer
         renderPassDescriptor:(MTLRenderPassDescriptor *)descriptor {
    if (_model == nullptr || !_rendererReady) { return; }
    CubismRenderer_Metal *const renderer =
        _model->GetRenderer<CubismRenderer_Metal>();
    if (renderer == nullptr) { return; }

    // Fit to the drawable while keeping her aspect: the model's own coordinate
    // space is roughly -1...1, so the projection only has to correct for the
    // view being taller than it is wide.
    const float width = static_cast<float>(MAX(_drawableSize.width, 1));
    const float height = static_cast<float>(MAX(_drawableSize.height, 1));
    CubismMatrix44 projection;
    if (width >= height) {
        projection.Scale(height / width, 1.0f);
    } else {
        projection.Scale(1.0f, width / height);
    }
    if (_model->Matrix() != nullptr) {
        projection.MultiplyByMatrix(_model->Matrix());
    }

    renderer->SetRenderViewport(
        MTLViewport{0.0, 0.0, _drawableSize.width, _drawableSize.height, 0.0, 1.0});
    renderer->SetMvpMatrix(&projection);
    renderer->StartFrame(commandBuffer, descriptor);
    renderer->DrawModel();
}

// MARK: - Diagnostics

+ (NSString *)coreVersion {
    const unsigned int v = Core::csmGetVersion();
    return [NSString stringWithFormat:@"%u.%u.%u",
                                      (v >> 24) & 0xFF, (v >> 16) & 0xFF, v & 0xFFFF];
}

+ (NSInteger)latestSupportedMocVersion {
    return static_cast<NSInteger>(Core::csmGetLatestMocVersion());
}

@end
