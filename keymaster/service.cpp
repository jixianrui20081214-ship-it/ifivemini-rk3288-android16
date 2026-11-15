// Keymaster 4.0 service for the iFive mini 4S: AOSP's software Keymaster
// (system/keymaster, android-11.0.0_r48) behind IKeymasterDevice/default.
// The board has no TEE; the Rockchip OP-TEE keymaster cannot run. The device
// reports TRUSTED_ENVIRONMENT because keystore2 needs a TEE-level KeyMint or
// Keymaster to start. Logs go to logd through SoftKeymasterLogger.
#define LOG_TAG "android.hardware.keymaster@4.0-service.ifive"

#include <android-base/logging.h>
#include <android/hardware/keymaster/4.0/IKeymasterDevice.h>
#include <hidl/HidlTransportSupport.h>
#include <keymaster/soft_keymaster_logger.h>

#include <AndroidKeymaster4Device.h>

using android::hardware::keymaster::V4_0::SecurityLevel;

int main() {
    keymaster::SoftKeymasterLogger logger;
    ::android::hardware::configureRpcThreadpool(1, true /* willJoinThreadpool */);
    auto keymaster = ::keymaster::V4_0::ng::CreateKeymasterDevice(SecurityLevel::TRUSTED_ENVIRONMENT);
    auto status = keymaster->registerAsService();
    if (status != android::OK) {
        LOG(FATAL) << "Could not register service for Keymaster 4.0 (" << status << ")";
    }
    android::hardware::joinRpcThreadpool();
    return -1;
}
