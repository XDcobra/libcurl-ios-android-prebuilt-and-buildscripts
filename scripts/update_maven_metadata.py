#!/usr/bin/env python3
"""
Update maven-metadata.xml with new version information.
Maintains and sorts version directories.
"""
import os
import sys
import datetime
import xml.etree.ElementTree as ET

def update_maven_metadata(group_id, artifact_id, version, artifact_dir):
    """Update or create maven-metadata.xml for a given artifact."""
    metadata_path = os.path.join(artifact_dir, 'maven-metadata.xml')
    
    # Collect all available versions in the directory
    versions = []
    if os.path.exists(artifact_dir):
        for item in os.listdir(artifact_dir):
            item_path = os.path.join(artifact_dir, item)
            # Check if it's a directory with POM files (indicating a version)
            if (os.path.isdir(item_path) and 
                any(f.endswith('.pom') for f in os.listdir(item_path))):
                versions.append(item)
    
    if version not in versions:
        versions.append(version)
    
    # Sort versions properly
    def version_key(v):
        import re
        return [int(x) if x.isdigit() else x 
                for x in re.split(r'[^0-9A-Za-z]', v)]
    versions.sort(key=version_key)
    
    # Load or create XML
    if os.path.exists(metadata_path):
        tree = ET.parse(metadata_path)
        root = tree.getroot()
    else:
        root = ET.Element('metadata')
        ET.SubElement(root, 'groupId').text = group_id
        ET.SubElement(root, 'artifactId').text = artifact_id
        tree = ET.ElementTree(root)
    
    # Update versioning section
    versioning = root.find('versioning')
    if versioning is None:
        versioning = ET.SubElement(root, 'versioning')
    
    # Update latest and release
    v_latest = versioning.find('latest')
    if v_latest is None:
        v_latest = ET.SubElement(versioning, 'latest')
    v_latest.text = version
    
    v_release = versioning.find('release')
    if v_release is None:
        v_release = ET.SubElement(versioning, 'release')
    v_release.text = version
    
    # Update versions list
    versions_node = versioning.find('versions')
    if versions_node is None:
        versions_node = ET.SubElement(versioning, 'versions')
    
    versions_node.clear()
    for v in versions:
        ET.SubElement(versions_node, 'version').text = v
    
    # Update timestamp
    last_updated = versioning.find('lastUpdated')
    if last_updated is None:
        last_updated = ET.SubElement(versioning, 'lastUpdated')
    last_updated.text = datetime.datetime.now(
        datetime.timezone.utc).strftime('%Y%m%d%H%M%S')
    
    # Pretty-print XML
    try:
        ET.indent(tree, space='  ')
    except AttributeError:
        # Fallback for older Python versions
        def indent_elem(elem, level=0):
            indent_str = "  " * level
            if len(elem):
                if not elem.text or not elem.text.strip():
                    elem.text = "\n" + indent_str + "  "
                if not elem.tail or not elem.tail.strip():
                    elem.tail = "\n" + indent_str
                for child in elem:
                    indent_elem(child, level + 1)
                if not child.tail or not child.tail.strip():
                    child.tail = "\n" + indent_str
            else:
                if level and (not elem.tail or not elem.tail.strip()):
                    elem.tail = "\n" + indent_str
        indent_elem(root)
    
    # Write to file
    with open(metadata_path, 'w', encoding='utf-8') as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        tree.write(f, encoding='unicode')

if __name__ == '__main__':
    if len(sys.argv) != 5:
        print("Usage: update_maven_metadata.py <group_id> <artifact_id> "
              "<version> <artifact_dir>")
        sys.exit(1)
    
    group_id = sys.argv[1]
    artifact_id = sys.argv[2]
    version = sys.argv[3]
    artifact_dir = sys.argv[4]
    
    update_maven_metadata(group_id, artifact_id, version, artifact_dir)
    print(f"Updated maven-metadata.xml for {group_id}:{artifact_id}:{version}")
