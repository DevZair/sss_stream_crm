import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    tasks.withType<JavaCompile>().configureEach {
        if ("-Xlint:-options" !in options.compilerArgs) {
            options.compilerArgs.add("-Xlint:-options")
        }
    }
}

// connectycube_flutter_call_kit тянет Kotlin JVM 21 при Java 17 — выравниваем только этот модуль.
gradle.projectsEvaluated {
    rootProject.subprojects
        .find { it.name == "connectycube_flutter_call_kit" }
        ?.tasks
        ?.withType<KotlinCompile>()
        ?.configureEach {
            compilerOptions.jvmTarget.set(JvmTarget.JVM_17)
        }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
