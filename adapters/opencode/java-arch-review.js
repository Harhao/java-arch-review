/**
 * OpenCode plugin for java-arch-review skill.
 * Injects the skill path into OpenCode's skill discovery.
 */
module.exports = {
  name: "java-arch-review",

  config(config) {
    const path = require("path");
    const skillsDir = path.resolve(__dirname, "..");

    config.skills = config.skills || {};
    config.skills.paths = config.skills.paths || [];

    if (!config.skills.paths.includes(skillsDir)) {
      config.skills.paths.push(skillsDir);
    }

    return config;
  },
};
