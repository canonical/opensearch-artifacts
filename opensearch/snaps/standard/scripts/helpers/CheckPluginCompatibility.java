import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import org.opensearch.plugins.PluginInfo;
import org.opensearch.plugins.PluginsService;

// Use the target snap's OpenSearch classes to check plugins copied into the new revision.
public class CheckPluginCompatibility {
    // Pass the shipped-plugins directory, the modules directory, then the custom plugin paths.
    // Print paths to remove on stdout, separated by NUL bytes, and explain each removal on stderr.
    // Finding an incompatible plugin is a successful check; the refresh hook handles its removal.
    public static void main(String[] arguments) throws IOException {
        Set<String> bundledPluginNames = new HashSet<>();

        // Collect the names already provided by the new snap's plugins and built-in modules.
        for (int bundledDirectoryIndex = 0; bundledDirectoryIndex < 2; bundledDirectoryIndex++) {
            // Close the directory stream when we have finished reading its entries.
            try (var bundledDirectories = Files.list(Path.of(arguments[bundledDirectoryIndex]))) {
                // Read the declared plugin name, which need not match its directory name.
                for (Path bundledPluginPath : bundledDirectories.filter(Files::isDirectory).toList()) {
                    bundledPluginNames.add(PluginInfo.readFromProperties(bundledPluginPath).getName());
                }
            }
        }
        Map<Path, PluginInfo> compatibleCustomPlugins = new LinkedHashMap<>();
        Map<Path, String> pluginRemovalReasons = new LinkedHashMap<>();

        // Check every custom plugin with the descriptor parser and compatibility rules
        // from the OpenSearch version in the new snap, rather than copying those rules here.
        for (int customPluginIndex = 2; customPluginIndex < arguments.length; customPluginIndex++) {
            Path customPluginPath = Path.of(arguments[customPluginIndex]);

            // Keep plugins that pass the native checks for the remaining checks below.
            try {
                PluginInfo pluginInfo = PluginInfo.readFromProperties(customPluginPath);
                PluginsService.verifyCompatibility(pluginInfo);
                compatibleCustomPlugins.put(customPluginPath, pluginInfo);
            // A missing or invalid descriptor, or an incompatible version, means this
            // plugin's new copy must be removed. Continue checking the other plugins.
            } catch (IOException | RuntimeException compatibilityFailure) {
                pluginRemovalReasons.put(customPluginPath, compatibilityFailure.toString());
            }
        }

        // A new snap may bundle a plugin or module that was previously installed as a custom plugin.
        // Keep the bundled version when its declared name matches, even if the directory names differ.
        compatibleCustomPlugins.forEach((customPluginPath, pluginInfo) -> {
            if (bundledPluginNames.contains(pluginInfo.getName())) {
                pluginRemovalReasons.put(customPluginPath, "Duplicate plugin name: " + pluginInfo.getName());
            }
        });

        // Removing a plugin may leave another plugin without a required dependency.
        // Repeat until no more removals are needed, including through dependency chains.
        boolean foundMissingDependency;
        do {
            foundMissingDependency = false;
            Set<String> availablePluginNames = new HashSet<>(bundledPluginNames);

            // Only count custom plugins that are still going to be kept.
            compatibleCustomPlugins.forEach((customPluginPath, pluginInfo) -> {
                // A plugin scheduled for removal cannot satisfy another plugin's dependency.
                if (!pluginRemovalReasons.containsKey(customPluginPath)) availablePluginNames.add(pluginInfo.getName());
            });

            // Check the dependencies of every remaining custom plugin.
            for (var customPluginEntry : compatibleCustomPlugins.entrySet()) {
                // Plugins already scheduled for removal need no further checks.
                if (pluginRemovalReasons.containsKey(customPluginEntry.getKey())) continue;
                PluginInfo pluginInfo = customPluginEntry.getValue();

                // Missing optional dependencies are allowed; required dependencies must remain available.
                for (String dependencyPluginName : pluginInfo.getExtendedPlugins()) {
                    // One missing required dependency is enough to remove this plugin's new copy.
                    if (!availablePluginNames.contains(dependencyPluginName)
                        && !pluginInfo.isExtendedPluginOptional(dependencyPluginName)) {
                        pluginRemovalReasons.put(customPluginEntry.getKey(), "Missing required plugin: " + dependencyPluginName);
                        foundMissingDependency = true;
                        break;
                    }
                }
            }
        } while (foundMissingDependency);

        // Give the hook the directories to remove, keeping explanations out of its path list.
        for (var removalEntry : pluginRemovalReasons.entrySet()) {
            System.err.println("Unloading new-revision copy of " + removalEntry.getKey() + ": " + removalEntry.getValue());
            System.out.print(removalEntry.getKey().toString());
            System.out.write(0);
        }

        // Flush the final NUL byte too, so the hook can read the last path in the list.
        System.out.flush();

        // Report a broken output stream as a checker failure so the hook uses its fallback.
        if (System.out.checkError()) throw new IOException("Cannot write plugin plan");
    }
}
