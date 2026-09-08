{{flutter_js}}
{{flutter_build_config}}

// Force every web deployment to load a fresh Dart entrypoint.
// This prevents a browser from reusing an older cached main.dart.js.
if (_flutter.buildConfig && Array.isArray(_flutter.buildConfig.builds)) {
  const cacheBust = Date.now().toString();
  for (const build of _flutter.buildConfig.builds) {
    if (build.mainJsPath) {
      build.mainJsPath = build.mainJsPath.includes('?')
          ? `${build.mainJsPath}&v=${cacheBust}`
          : `${build.mainJsPath}?v=${cacheBust}`;
    }
  }
}

_flutter.loader.load();
