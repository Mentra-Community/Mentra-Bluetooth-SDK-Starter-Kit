pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
val mentraBluetoothSdkRoot = providers.environmentVariable("MENTRA_BLUETOOTH_SDK_PACKAGE_PATH").orNull
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
