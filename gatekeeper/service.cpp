// Entry point for the iFive mini 4S software gatekeeper. Same as AOSP's
// hardware/interfaces/gatekeeper/aidl/software/service.cpp, except that it logs
// to logd: the service runs as user system, which cannot open /dev/kmsg (0600
// root), so the AOSP KernelLogger output was lost.
#define LOG_TAG "android.hardware.gatekeeper-service.ifive"

#include <android-base/logging.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>

#include "GateKeeper.h"
#include "SharedSecret.h"
#include "SoftGateKeeper.h"

using aidl::android::hardware::gatekeeper::SoftGateKeeperDevice;
using aidl::android::hardware::security::sharedsecret::SoftSharedSecret;

int main(int, char** argv) {
    ::android::base::InitLogging(argv, ::android::base::LogdLogger(::android::base::SYSTEM));
    ABinderProcess_setThreadPoolMaxThreadCount(0);

    auto secret = ndk::SharedRefBase::make<SoftSharedSecret>();
    std::string secret_instance = SoftSharedSecret::descriptor + std::string("/gatekeeper");
    auto status = AServiceManager_addService(secret->asBinder().get(), secret_instance.c_str());
    CHECK_EQ(status, STATUS_OK);

    ::gatekeeper::SoftGateKeeper implementation(*secret);
    auto gatekeeper = ndk::SharedRefBase::make<SoftGateKeeperDevice>(implementation);
    const std::string instance = SoftGateKeeperDevice::descriptor + std::string("/default");
    status = AServiceManager_addService(gatekeeper->asBinder().get(), instance.c_str());
    CHECK_EQ(status, STATUS_OK);

    ABinderProcess_joinThreadPool();
    return -1;
}
