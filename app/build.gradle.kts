plugins {
    id("com.android.application")
    kotlin("android")
}

android {
    namespace = "com.example.slutwalk"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.slutwalk"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
        }
        getByName("release") {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/*.kotlin_module"
            )
        }
    }

    buildFeatures {
        viewBinding = true
    }
}

configurations.all {
    resolutionStrategy {
        // Harte Pins verhindern Downgrades auf 1.0.x/1.1.x
        force(
            "androidx.core:core-ktx:1.13.1",
            "androidx.appcompat:appcompat:1.6.1",
            "com.google.android.material:material:1.11.0",
            "androidx.constraintlayout:constraintlayout:2.1.4",
            "androidx.recyclerview:recyclerview:1.3.2",
            "androidx.activity:activity-ktx:1.9.0",
            "androidx.lifecycle:lifecycle-runtime-ktx:2.8.2",
            "androidx.transition:transition:1.4.1",
            "androidx.viewpager2:viewpager2:1.0.0"
        )
        // Verhindert falsche alte Legacy-Transitives
        eachDependency {
            if (requested.group == "com.google.android.material" && requested.name == "material") {
                useVersion("1.11.0")
                because("Material 1.11.0 eliminiert alte legacy-support Abhängigkeiten")
            }
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("androidx.activity:activity-ktx:1.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.2")

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}
