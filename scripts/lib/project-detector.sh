#!/usr/bin/env bash
# project-detector.sh - Detect Java/Spring Boot project structure and output JSON metadata
#
# Provides: detect_project PROJECT_PATH
# Outputs:  JSON object with project metadata to stdout
#
# Sourced by arch-review.sh; requires common.sh for json_escape.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

###############################################################################
# Public API
###############################################################################

# detect_project PROJECT_PATH
#   Analyse a Java project directory and print a JSON metadata object.
detect_project() {
  local project_path="${1:-.}"
  project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
    echo '{"error":"Invalid project path"}' >&2
    return 1
  }

  # --- Build tool -----------------------------------------------------------
  local build_tool="null"
  if [[ -f "$project_path/pom.xml" ]]; then
    build_tool="maven"
  elif [[ -f "$project_path/build.gradle" ]] || [[ -f "$project_path/build.gradle.kts" ]]; then
    build_tool="gradle"
  fi

  # --- Core metadata --------------------------------------------------------
  local project_name
  project_name=$(_detect_project_name "$project_path" "$build_tool")

  local spring_boot_version
  spring_boot_version=$(_detect_spring_boot_version "$project_path" "$build_tool")

  local java_version
  java_version=$(_detect_java_version "$project_path" "$build_tool")

  local orm
  orm=$(_detect_orm "$project_path" "$build_tool")

  local modules_json
  modules_json=$(_detect_modules "$project_path" "$build_tool")

  # --- Counts ---------------------------------------------------------------
  local source_files test_files
  source_files=$(_count_java_files "$project_path" "src/main")
  test_files=$(_count_java_files "$project_path" "src/test")

  # --- Capabilities ---------------------------------------------------------
  local has_redis
  has_redis=$(_detect_redis "$project_path" "$build_tool")

  local has_docker=false
  if [[ -f "$project_path/Dockerfile" ]] \
    || [[ -f "$project_path/docker-compose.yml" ]] \
    || [[ -f "$project_path/docker-compose.yaml" ]]; then
    has_docker=true
  fi

  # --- Roots ----------------------------------------------------------------
  local source_root resource_root
  source_root=$(_detect_source_root "$project_path" "$build_tool")
  resource_root=$(_detect_resource_root "$project_path" "$build_tool")

  # --- JSON output ----------------------------------------------------------
  cat <<EOF
{
  "path": "$(json_escape "$project_path")",
  "name": "$(json_escape "$project_name")",
  "springBootVersion": $(_json_str_or_null "$spring_boot_version"),
  "orm": $(_json_str_or_null "$orm"),
  "javaVersion": $(_json_str_or_null "$java_version"),
  "modules": ${modules_json},
  "sourceFiles": ${source_files},
  "testFiles": ${test_files},
  "buildTool": $(_json_str_or_null "$build_tool"),
  "hasRedis": ${has_redis},
  "hasDocker": ${has_docker},
  "sourceRoot": $(_json_str_or_null "$source_root"),
  "resourceRoot": $(_json_str_or_null "$resource_root")
}
EOF
}

###############################################################################
# Internal helpers
###############################################################################

# _json_str_or_null VALUE
#   Print a JSON-escaped string, or the literal `null` when VALUE is empty or "null".
_json_str_or_null() {
  if [[ -z "$1" || "$1" == "null" ]]; then
    echo "null"
  else
    printf '"%s"' "$(json_escape "$1")"
  fi
}

# ---------------------------------------------------------------------------
# Project name
# ---------------------------------------------------------------------------
_detect_project_name() {
  local project_path="$1" build_tool="$2"
  local name=""

  if [[ "$build_tool" == "maven" && -f "$project_path/pom.xml" ]]; then
    # Extract <artifactId> that is a direct child of <project>, skipping <parent> block.
    name=$(awk '
      /<parent>/       { in_parent=1 }
      /<\/parent>/     { in_parent=0; next }
      !in_parent && /<artifactId>/ {
        gsub(/.*<artifactId>/, ""); gsub(/<\/artifactId>.*/, ""); print; exit
      }
    ' "$project_path/pom.xml")
  elif [[ "$build_tool" == "gradle" ]]; then
    local settings_file=""
    [[ -f "$project_path/settings.gradle" ]]     && settings_file="$project_path/settings.gradle"
    [[ -f "$project_path/settings.gradle.kts" ]] && settings_file="$project_path/settings.gradle.kts"
    if [[ -n "$settings_file" ]]; then
      name=$(sed -n "s/.*rootProject\.name[[:space:]]*=[[:space:]]*['\"\`]//p" "$settings_file" \
             | sed "s/['\"\`].*//" | head -1)
    fi
  fi

  # Fallback: directory name
  if [[ -z "$name" ]]; then
    name=$(basename "$project_path")
  fi

  echo "$name"
}

# ---------------------------------------------------------------------------
# Spring Boot version
# ---------------------------------------------------------------------------
_detect_spring_boot_version() {
  local project_path="$1" build_tool="$2"
  local version=""

  if [[ "$build_tool" == "maven" && -f "$project_path/pom.xml" ]]; then
    # Strategy 1 – <parent> with spring-boot-starter-parent
    version=$(_extract_parent_spring_boot_version "$project_path/pom.xml")

    # Strategy 2 – spring-boot-dependencies in <dependencyManagement>
    if [[ -z "$version" ]]; then
      version=$(awk '
        /spring-boot-dependencies/ { found=1 }
        found && /<version>/ {
          gsub(/.*<version>/, ""); gsub(/<\/version>.*/, ""); print; exit
        }
      ' "$project_path/pom.xml")
    fi

    # Resolve ${property} references
    if [[ "$version" == *'${'* ]]; then
      version=$(_resolve_maven_property "$project_path/pom.xml" "$version")
    fi
  elif [[ "$build_tool" == "gradle" ]]; then
    local gradle_file=""
    [[ -f "$project_path/build.gradle" ]]     && gradle_file="$project_path/build.gradle"
    [[ -f "$project_path/build.gradle.kts" ]] && gradle_file="$project_path/build.gradle.kts"

    if [[ -n "$gradle_file" ]]; then
      # id 'org.springframework.boot' version 'X.Y.Z'  /  id("...") version "..."
      version=$(grep "org.springframework.boot" "$gradle_file" \
                | grep -oE "[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9._-]*" | head -1)
    fi
  fi

  echo "$version"
}

# Helper: extract version from <parent> block containing spring-boot-starter-parent
_extract_parent_spring_boot_version() {
  local pom_file="$1"
  awk '
    /<parent>/  { in_parent=1; version="" }
    /<\/parent>/ {
      if (in_parent && is_sb) { print version }
      in_parent=0; is_sb=0
    }
    in_parent && /spring-boot-starter-parent/ { is_sb=1 }
    in_parent && /<version>/ {
      v = $0
      gsub(/.*<version>/, "", v); gsub(/<\/version>.*/, "", v)
      version = v
    }
  ' "$pom_file"
}

# Helper: resolve a ${prop.name} against <properties> in pom.xml
_resolve_maven_property() {
  local pom_file="$1" raw="$2"
  local prop_name
  prop_name=$(echo "$raw" | sed 's/.*${\([^}]*\)}.*/\1/')
  # Escape dots for awk regex
  local prop_pattern
  prop_pattern=$(echo "$prop_name" | sed 's/\./\\./g')
  awk -v pat="$prop_pattern" '
    $0 ~ "<"pat">" {
      gsub(".*<"pat">", ""); gsub("</"pat">.*", ""); print; exit
    }
  ' "$pom_file"
}

# ---------------------------------------------------------------------------
# Java version
# ---------------------------------------------------------------------------
_detect_java_version() {
  local project_path="$1" build_tool="$2"
  local version=""

  if [[ "$build_tool" == "maven" && -f "$project_path/pom.xml" ]]; then
    # 1. <java.version>
    version=$(sed -n 's/.*<java\.version>\([^<]*\)<\/java\.version>.*/\1/p' \
              "$project_path/pom.xml" | head -1)
    # 2. <maven.compiler.source>
    if [[ -z "$version" ]]; then
      version=$(sed -n 's/.*<maven\.compiler\.source>\([^<]*\)<\/maven\.compiler\.source>.*/\1/p' \
                "$project_path/pom.xml" | head -1)
    fi
    # 3. <maven.compiler.release>
    if [[ -z "$version" ]]; then
      version=$(sed -n 's/.*<maven\.compiler\.release>\([^<]*\)<\/maven\.compiler\.release>.*/\1/p' \
                "$project_path/pom.xml" | head -1)
    fi
  elif [[ "$build_tool" == "gradle" ]]; then
    local gradle_file=""
    [[ -f "$project_path/build.gradle" ]]     && gradle_file="$project_path/build.gradle"
    [[ -f "$project_path/build.gradle.kts" ]] && gradle_file="$project_path/build.gradle.kts"

    if [[ -n "$gradle_file" ]]; then
      # sourceCompatibility = '17'  or  sourceCompatibility = JavaVersion.VERSION_17
      version=$(grep -E "sourceCompatibility" "$gradle_file" \
                | sed "s/.*=[[:space:]]*//" \
                | sed "s/^['\"]//; s/['\"].*//; s/JavaVersion\.VERSION_//" \
                | tr -d ' ' | head -1)
    fi
  fi

  echo "$version"
}

# ---------------------------------------------------------------------------
# ORM detection
# ---------------------------------------------------------------------------
_detect_orm() {
  local project_path="$1" build_tool="$2"
  local deps_content=""

  if [[ "$build_tool" == "maven" ]]; then
    deps_content=$(_collect_pom_contents "$project_path")
  elif [[ "$build_tool" == "gradle" ]]; then
    deps_content=$(_collect_gradle_contents "$project_path")
  fi

  if [[ -z "$deps_content" ]]; then
    echo ""
    return
  fi

  # Priority order: mybatis-plus > mybatis > jpa > jdbc
  if echo "$deps_content" | grep -qi "mybatis-plus"; then
    echo "mybatis-plus"
  elif echo "$deps_content" | grep -qi "mybatis"; then
    echo "mybatis"
  elif echo "$deps_content" | grep -qi "spring-data-jpa\|hibernate-core\|jakarta\.persistence\|javax\.persistence"; then
    echo "jpa"
  elif echo "$deps_content" | grep -qi "spring-boot-starter-jdbc\|spring-jdbc"; then
    echo "jdbc"
  else
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# Redis detection
# ---------------------------------------------------------------------------
_detect_redis() {
  local project_path="$1" build_tool="$2"
  local deps_content=""

  if [[ "$build_tool" == "maven" ]]; then
    deps_content=$(_collect_pom_contents "$project_path")
  elif [[ "$build_tool" == "gradle" ]]; then
    deps_content=$(_collect_gradle_contents "$project_path")
  fi

  if echo "$deps_content" | grep -qi "spring-boot-starter-data-redis\|jedis\|lettuce-core"; then
    echo "true"
  else
    echo "false"
  fi
}

# ---------------------------------------------------------------------------
# Module detection
# ---------------------------------------------------------------------------
_detect_modules() {
  local project_path="$1" build_tool="$2"

  if [[ "$build_tool" == "maven" ]]; then
    _detect_maven_modules "$project_path"
  elif [[ "$build_tool" == "gradle" ]]; then
    _detect_gradle_modules "$project_path"
  else
    echo "[]"
  fi
}

_detect_maven_modules() {
  local project_path="$1"
  local raw_modules
  raw_modules=$(_get_maven_module_names "$project_path")

  if [[ -z "$raw_modules" ]]; then
    echo "[]"
    return
  fi

  local json="["
  local first=true
  while IFS= read -r mod; do
    [[ -z "$mod" ]] && continue
    # Only include modules whose directory actually exists
    if [[ -d "$project_path/$mod" ]]; then
      if [[ "$first" == true ]]; then
        first=false
      else
        json+=","
      fi
      json+="\"$(json_escape "$mod")\""
    fi
  done <<< "$raw_modules"
  json+="]"

  echo "$json"
}

_detect_gradle_modules() {
  local project_path="$1"
  local settings_file=""
  [[ -f "$project_path/settings.gradle" ]]     && settings_file="$project_path/settings.gradle"
  [[ -f "$project_path/settings.gradle.kts" ]] && settings_file="$project_path/settings.gradle.kts"

  if [[ -z "$settings_file" ]]; then
    echo "[]"
    return
  fi

  # Parse include/include() lines: include 'mod1', 'mod2'  or  include(":mod1")
  local raw_modules
  raw_modules=$(grep -E "^[[:space:]]*include" "$settings_file" \
    | sed "s/include[[:space:]]*(//g; s/)//g; s/include//g" \
    | tr ',' '\n' \
    | sed "s/['\"\`:]//g; s/^[[:space:]]*//; s/[[:space:]]*$//" \
    | grep -v '^$')

  if [[ -z "$raw_modules" ]]; then
    echo "[]"
    return
  fi

  local json="["
  local first=true
  while IFS= read -r mod; do
    [[ -z "$mod" ]] && continue
    if [[ -d "$project_path/$mod" ]]; then
      if [[ "$first" == true ]]; then
        first=false
      else
        json+=","
      fi
      json+="\"$(json_escape "$mod")\""
    fi
  done <<< "$raw_modules"
  json+="]"

  echo "$json"
}

# ---------------------------------------------------------------------------
# File counting
# ---------------------------------------------------------------------------
_count_java_files() {
  local project_path="$1" sub_path="$2"
  local count=0

  # Direct (single module)
  if [[ -d "$project_path/$sub_path" ]]; then
    local c
    c=$(find "$project_path/$sub_path" -name "*.java" -type f 2>/dev/null | wc -l | tr -d ' ')
    count=$((count + c))
  fi

  # Submodules
  local modules
  modules=$(_get_maven_module_names "$project_path")
  if [[ -n "$modules" ]]; then
    while IFS= read -r mod; do
      [[ -z "$mod" ]] && continue
      if [[ -d "$project_path/$mod/$sub_path" ]]; then
        local c
        c=$(find "$project_path/$mod/$sub_path" -name "*.java" -type f 2>/dev/null | wc -l | tr -d ' ')
        count=$((count + c))
      fi
    done <<< "$modules"
  fi

  echo "$count"
}

# ---------------------------------------------------------------------------
# Source / resource root detection
# ---------------------------------------------------------------------------
_detect_source_root() {
  local project_path="$1" build_tool="$2"

  # Direct
  if [[ -d "$project_path/src/main/java" ]]; then
    echo "src/main/java"
    return
  fi

  # First submodule that has the path
  local modules
  modules=$(_get_all_module_names "$project_path" "$build_tool")
  if [[ -n "$modules" ]]; then
    while IFS= read -r mod; do
      [[ -z "$mod" ]] && continue
      if [[ -d "$project_path/$mod/src/main/java" ]]; then
        echo "$mod/src/main/java"
        return
      fi
    done <<< "$modules"
  fi

  echo ""
}

_detect_resource_root() {
  local project_path="$1" build_tool="$2"

  if [[ -d "$project_path/src/main/resources" ]]; then
    echo "src/main/resources"
    return
  fi

  local modules
  modules=$(_get_all_module_names "$project_path" "$build_tool")
  if [[ -n "$modules" ]]; then
    while IFS= read -r mod; do
      [[ -z "$mod" ]] && continue
      if [[ -d "$project_path/$mod/src/main/resources" ]]; then
        echo "$mod/src/main/resources"
        return
      fi
    done <<< "$modules"
  fi

  echo ""
}

# ---------------------------------------------------------------------------
# Dependency content collectors
# ---------------------------------------------------------------------------
_collect_pom_contents() {
  local project_path="$1"
  local content=""

  if [[ -f "$project_path/pom.xml" ]]; then
    content=$(cat "$project_path/pom.xml")
  fi

  local modules
  modules=$(_get_maven_module_names "$project_path")
  if [[ -n "$modules" ]]; then
    while IFS= read -r mod; do
      [[ -z "$mod" ]] && continue
      if [[ -f "$project_path/$mod/pom.xml" ]]; then
        content="$content"$'\n'"$(cat "$project_path/$mod/pom.xml")"
      fi
    done <<< "$modules"
  fi

  echo "$content"
}

_collect_gradle_contents() {
  local project_path="$1"
  local content=""

  for f in "$project_path"/build.gradle "$project_path"/build.gradle.kts; do
    [[ -f "$f" ]] && content="$content"$'\n'"$(cat "$f")"
  done

  # Sub-project build files via settings
  local settings_file=""
  [[ -f "$project_path/settings.gradle" ]]     && settings_file="$project_path/settings.gradle"
  [[ -f "$project_path/settings.gradle.kts" ]] && settings_file="$project_path/settings.gradle.kts"

  if [[ -n "$settings_file" ]]; then
    local includes
    includes=$(grep -E "^[[:space:]]*include" "$settings_file" \
      | sed "s/include[[:space:]]*(//g; s/)//g; s/include//g" \
      | tr ',' '\n' \
      | sed "s/['\"\`:]//g; s/^[[:space:]]*//; s/[[:space:]]*$//" \
      | grep -v '^$')
    if [[ -n "$includes" ]]; then
      while IFS= read -r mod; do
        [[ -z "$mod" ]] && continue
        for f in "$project_path/$mod"/build.gradle "$project_path/$mod"/build.gradle.kts; do
          [[ -f "$f" ]] && content="$content"$'\n'"$(cat "$f")"
        done
      done <<< "$includes"
    fi
  fi

  echo "$content"
}

# ---------------------------------------------------------------------------
# Module name extractors
# ---------------------------------------------------------------------------

# Maven: read <module> elements from the root pom.xml
_get_maven_module_names() {
  local project_path="$1"
  [[ -f "$project_path/pom.xml" ]] || return
  sed -n 's/.*<module>\([^<]*\)<\/module>.*/\1/p' "$project_path/pom.xml"
}

# Unified: return module names regardless of build tool
_get_all_module_names() {
  local project_path="$1" build_tool="$2"

  if [[ "$build_tool" == "maven" ]]; then
    _get_maven_module_names "$project_path"
  elif [[ "$build_tool" == "gradle" ]]; then
    local settings_file=""
    [[ -f "$project_path/settings.gradle" ]]     && settings_file="$project_path/settings.gradle"
    [[ -f "$project_path/settings.gradle.kts" ]] && settings_file="$project_path/settings.gradle.kts"
    if [[ -n "$settings_file" ]]; then
      grep -E "^[[:space:]]*include" "$settings_file" \
        | sed "s/include[[:space:]]*(//g; s/)//g; s/include//g" \
        | tr ',' '\n' \
        | sed "s/['\"\`:]//g; s/^[[:space:]]*//; s/[[:space:]]*$//" \
        | grep -v '^$'
    fi
  fi
}
