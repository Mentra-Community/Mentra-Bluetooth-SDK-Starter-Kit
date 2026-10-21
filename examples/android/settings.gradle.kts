pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
// Same choice as scripts/mentraos-sdk-path.cjs: MENTRA_BLUETOOTH_SDK_PUBLISHED=1 forces
// the published SDK, then MENTRA_BLUETOOTH_SDK_PACKAGE_PATH, then a MentraOS checkout
// mobile workspace next to this repository (../mentraos/mobile).
val mentraBluetoothSdkRoot: String? = when {
    providers.environmentVariable("MENTRA_BLUETOOTH_SDK_PUBLISHED").orNull == "1" -> null
    else -> providers.environmentVariable("MENTRA_BLUETOOTH_SDK_PACKAGE_PATH").orNull?.takeIf { it.isNotBlank() }
        ?: file("../../../mentraos/mobile").takeIf { File(it, "package.json").isFile && File(it, "modules/bluetooth-sdk/package.json").isFile }
            ?.let { File(it, "modules/bluetooth-sdk").path }
}
gradle.extra["mentraBluetoothSdkRoot"] = mentraBluetoothSdkRoot
val useMavenLocal = providers.gradleProperty("mentraUseMavenLocal")
    .map(String::toBoolean)
    .orElse(false)
    .get()

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        if (!mentraBluetoothSdkRoot.isNullOrBlank()) {
            // The SDK's Gradle project needs an Expo host, so a source build uses
            // the artifacts published to Maven local from that checkout (README).
            exclusiveContent {
                forRepository { mavenLocal() }
                filter { includeGroup("com.mentraglass") }
            }
        } else if (useMavenLocal) {
            mavenLocal()
        }
        google()
        mavenCentral()
    }
}

rootProject.name = "MentraDesignerAndroidExample"
include(":app")
