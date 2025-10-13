import fs from 'fs';
import fetch from 'node-fetch';
import YAML from 'yaml';

interface Annotation {
    id: string;
    target: string | string[];  // <- changed
    [key: string]: any;
}

const serverBase = 'http://localhost:10000/annotations';

// Extract base canvas ID from a `target` string like "...canvas/123#xywh=..."
function extractCanvasIdFromTarget(target: string): string {
    const hashIndex = target.indexOf('#');
    return hashIndex >= 0 ? target.substring(0, hashIndex) : target;
}

// Load project configuration from YAML
function loadProjectConfig(projectName: string): any {
    try {
        const configPath = '../config/projects.yml';
        
        if (!fs.existsSync(configPath)) {
            console.warn(`⚠️ Configuration file not found: ${configPath}`);
            return getDefaultConfig(projectName);
        }
        
        const configFile = fs.readFileSync(configPath, 'utf8');
        const config = YAML.parse(configFile);
        
        // Get project-specific configuration
        const projectConfig = config.projects?.[projectName];
        if (!projectConfig) {
            console.warn(`⚠️ Project '${projectName}' not found in configuration, using defaults`);
            return getDefaultConfig(projectName);
        }
        
        // Merge with defaults
        const defaults = config.defaults || {};
        
        return {
            title: projectConfig.title || projectName,
            description: projectConfig.description || `Explore the ${projectName} collection`,
            metadata: projectConfig.metadata || [],
            provider: projectConfig.provider || defaults.provider || null
        };
    } catch (error) {
        console.warn(`⚠️ Error loading configuration for ${projectName}:`, error instanceof Error ? error.message : String(error));
        return getDefaultConfig(projectName);
    }
}

// Default configuration fallback
function getDefaultConfig(projectName: string): any {
    return {
        title: projectName,
        description: `Explore the ${projectName} collection`,
        metadata: [],
        provider: null
    };
}

function generateManifest(grouped: Record<string, Annotation[]>, manifestId: string, manifestName: string, projectName: string = 'Project', hostname: string = 'http://localhost:8080') {
    // Load project configuration
    const config = loadProjectConfig(projectName);
    
    const canvases = Object.entries(grouped).map(([canvasUrl, annotations]) => {
        const containerId = extractContainerId(canvasUrl);
        const imageId = canvasUrl.split('/').pop()?.replace('.json', '') ?? containerId;

        return {
            id: canvasUrl,
            type: 'Canvas',
            width: 3191,
            height: 4573,
            items: [
                {
                    id: `${canvasUrl}/painting`,
                    type: 'AnnotationPage',
                    items: [
                        {
                            id: `${hostname}/cantaloupe/iiif/manifest/${imageId}/annotation`,
                            type: 'Annotation',
                            motivation: 'painting',
                            target: canvasUrl,
                            body: {
                                id: `${hostname}/cantaloupe/iiif/3/${imageId}.tif/full/max/0/default.jpg`,
                                type: 'Image',
                                format: 'image/jpeg',
                                service: [
                                    {
                                        id: `${hostname}/cantaloupe/iiif/3/${imageId}.tif/info.json`,
                                        type: 'ImageService3',
                                        profile: 'level2'
                                    }
                                ]
                            }
                        }
                    ]
                }
            ],
            annotations: [
                {
                    id: `${hostname}/miiify/annotations/${containerId}/?page=0`,
                    type: 'AnnotationPage'
                }
            ]
        };
    });

    const manifest: any = {
        '@context': 'http://iiif.io/api/presentation/3/context.json',
        id: manifestId,
        type: 'Manifest',
        label: { en: [manifestName] }, // Keep title as filename
        items: canvases
    };

    // Add metadata from collection configuration to individual manifests
    if (config.metadata && config.metadata.length > 0) {
        manifest.metadata = config.metadata;
    }

    // Add provider if configured
    if (config.provider) {
        manifest.provider = [config.provider];
    }

    return manifest;
}

function generateCollection(manifestFiles: string[], projectName: string, hostname: string = 'http://localhost:8080'): any {
    const config = loadProjectConfig(projectName);
    const baseUrl = `${hostname}/iiif`;
    
    // Extract manifest names (without .json extension) for subjects
    const manifestNames = manifestFiles.map(file => file.replace('.json', ''));
    
    const items = manifestFiles.map(manifestFile => {
        const manifestName = manifestFile.replace('.json', '');
        return {
            id: `${baseUrl}/${manifestFile}`,
            type: 'Manifest',
            label: { en: [manifestName] }
        };
    });

    const collection: any = {
        '@context': 'http://iiif.io/api/presentation/3/context.json',
        id: `${baseUrl}/${projectName}.json`,
        type: 'Collection',
        label: { en: [config.title] },
        summary: { en: [config.description] },
        service: [
            {
                id: `${hostname}/annosearch/${projectName}/search`,
                type: 'SearchService2',
                service: [
                    {
                        id: `${hostname}/annosearch/${projectName}/autocomplete`,
                        type: 'AutoCompleteService2'
                    }
                ]
            }
        ],
        items: items
    };

    // Add metadata to collection
    if (config.metadata && config.metadata.length > 0) {
        // Create a copy of the metadata array
        collection.metadata = [...config.metadata];
        
        // Find existing subjects field or add new one
        let subjectsField = collection.metadata.find((meta: any) => 
            meta.label && meta.label.en && meta.label.en.includes('Subjects')
        );
        
        if (subjectsField) {
            // Add manifest names to existing subjects
            const existingSubjects = subjectsField.value.en || subjectsField.value.none || [];
            subjectsField.value = {
                en: [...existingSubjects, ...manifestNames]
            };
        } else {
            // Create new subjects field with manifest names
            collection.metadata.push({
                label: {
                    en: ["Subjects"]
                },
                value: {
                    en: manifestNames
                }
            });
        }
    } else {
        // If no metadata exists, create metadata with just subjects
        collection.metadata = [
            {
                label: {
                    en: ["Subjects"]
                },
                value: {
                    en: manifestNames
                }
            }
        ];
    }

    // Add provider to collection
    if (config.provider) {
        collection.provider = [config.provider];
    }

    return collection;
}

function sanitizeSlug(raw: string): string {
    return raw.replace(/\//g, '-');
}

function extractSlug(id: string): string {
    const parts = id.split('/').filter(Boolean);
    return sanitizeSlug(parts.slice(-2).join('/'));
}

function extractContainerId(canvasUrl: string): string {
    try {
        const url = new URL(canvasUrl);
        const path = url.pathname.replace(/^\/+/, '');
        return sanitizeSlug(path);
    } catch {
        return sanitizeSlug(encodeURIComponent(canvasUrl));
    }
}

async function deleteContainer(containerId: string): Promise<boolean> {
    const deleteUrl = `${serverBase}/${containerId}`;
    
    const deleteRes = await fetch(deleteUrl, {
        method: 'DELETE'
    });
    
    if (deleteRes.ok) {
        console.log(`🗑️ Deleted existing container: ${containerId}`);
        return true;
    } else if (deleteRes.status === 404) {
        return false;
    } else {
        console.warn(`❌ Failed to delete container ${containerId}: ${deleteRes.status} ${deleteRes.statusText}`);
        return false;
    }
}

async function createContainer(containerId: string): Promise<void> {
    const postUrl = `${serverBase}/`;
    
    const res = await fetch(postUrl, {
        method: 'POST',
        headers: {
            'Slug': containerId,
            'Content-Type': 'application/ld+json',
        },
        body: JSON.stringify({
            '@context': 'http://www.w3.org/ns/anno.jsonld',
            'type': 'AnnotationCollection',
            'label': `Annotations for ${containerId}`,
        }),
    });

    const responseText = await res.text();

    if (res.ok) {
        console.log(`✅ Created container: ${containerId}`);
        return;
    }

    // If it fails, let's see what the server actually says
    if (res.status === 400 && responseText.includes('container exists')) {
        // Check what's actually at this endpoint (using / for GET)
        const getUrl = `${serverBase}/${containerId}/`;
        const checkRes = await fetch(getUrl, { method: 'GET' });
        
        if (checkRes.ok) {
            console.log(`✅ Using existing container: ${containerId}`);
            return; // Use the existing container
        } else {
            console.log(`❓ Container supposedly exists but not accessible via GET`);
        }
    }
    
    // For any other error, just throw
    throw new Error(`Failed to create container ${containerId}: ${res.status} ${res.statusText} - ${responseText}`);
}

async function ensureContainer(containerId: string): Promise<void> {
    // First try to delete any existing container
    await deleteContainer(containerId);
    
    // Wait a moment for delete to propagate
    await new Promise(resolve => setTimeout(resolve, 200));
    
    try {
        // Try to create the container
        await createContainer(containerId);
    } catch (error: any) {
        if (error.message.includes('container exists')) {
            console.log(`⚠️ Container ${containerId} still exists after delete. Checking if we can use it...`);
            
            // Try to GET the container to see if it's actually usable
            const checkRes = await fetch(`${serverBase}/${containerId}/`, { method: 'GET' });
            if (checkRes.ok) {
                console.log(`✅ Using existing container: ${containerId}`);
                return; // Use the existing container
            } else {
                console.log(`❌ Container exists but not accessible: ${checkRes.status}`);
                throw error; // Re-throw the original error
            }
        } else {
            throw error; // Re-throw non-existence errors
        }
    }
}

async function ensureAnnotation(containerId: string, annotation: Annotation): Promise<void> {
    const slug = extractSlug(annotation.id);
    
    // Create the annotation directly (since container was freshly created)
    const annotationCopy = JSON.parse(JSON.stringify(annotation));
    delete annotationCopy.id;

    const postUrl = `${serverBase}/${containerId}/`;

    const res = await fetch(postUrl, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/ld+json',
            'Slug': slug,
        },
        body: JSON.stringify(annotationCopy),
    });

    if (!res.ok) {
        const errorText = await res.text();
        
        // If it says annotation exists, flag it
        if (res.status === 400 && errorText.includes('annotation exists')) {
            console.log(`🚩 WARNING: Annotation ${slug} already exists (container may not have been properly cleared)`);
            return;
        }
        
        console.warn(`❌ Failed to post annotation ${slug}: ${res.status} ${res.statusText}`);
        console.warn(`Server response: ${errorText}`);
        throw new Error(`Failed to post annotation ${slug}`);
    } else {
        console.log(`✅ Posted annotation: ${slug}`);
    }
}

async function uploadAllAnnotations() {
    // Get command line arguments for project name, always use localhost for manifests
    const args = process.argv.slice(2);
    const projectName = args[0] || 'lincolnshire';
    const hostname = 'http://localhost:8080';  // Always use localhost for manifests
    
    console.log(`🎯 Loading annotations for project: ${projectName}`);
    
    // Find all annotation files in web/annotations directory
    const webAnnotationsDir = '../web/annotations';
    if (!fs.existsSync(webAnnotationsDir)) {
        console.error('❌ No annotation files found in web/annotations/');
        console.error('📝 Please place your .json annotation files in web/annotations/');
        return;
    }
    
    const annotationFiles = fs.readdirSync(webAnnotationsDir)
        .filter(f => f.endsWith('.json') && f !== '.gitkeep');
    
    if (annotationFiles.length === 0) {
        console.error('❌ No annotation files found in web/annotations/');
        console.error('� Please place your .json annotation files in web/annotations/');
        return;
    }
    
    console.log(`� Found ${annotationFiles.length} annotation file(s): ${annotationFiles.join(', ')}`);
    
    const manifestFiles: string[] = [];
    
    // Process each annotation file to create individual manifests
    for (const annotationFile of annotationFiles) {
        const manifestName = annotationFile.replace('.json', '');
        console.log(`\n� Processing manifest: ${manifestName}`);
        
        const annotationFilePath = `${webAnnotationsDir}/${annotationFile}`;
        const raw = fs.readFileSync(annotationFilePath, 'utf-8');
        const annotationPage = JSON.parse(raw);
        
        // Extract annotations from the AnnotationPage items array
        const annotations: Annotation[] = annotationPage.items || annotationPage;
        console.log(`� Loaded ${annotations.length} annotations from ${annotationFile}`);

        const grouped: Record<string, Annotation[]> = {};

        for (const anno of annotations) {
            const targets = Array.isArray(anno.target) ? anno.target : [anno.target];
            for (const t of targets) {
                const canvas = extractCanvasIdFromTarget(t);
                if (!grouped[canvas]) grouped[canvas] = [];
                grouped[canvas].push(anno);
            }
        }

        // Upload annotations to miiify
        for (const [canvas, annos] of Object.entries(grouped)) {
            const containerId = extractContainerId(canvas);
            console.log(`📦 Processing container: ${containerId} (${annos.length} annotations)`);
            await ensureContainer(containerId);
            for (const anno of annos) {
                await ensureAnnotation(containerId, anno);
            }
        }

        // Generate individual manifest using localhost only
        const manifestFile = `${manifestName}.json`;
        const localhostUrl = 'http://localhost:8080';
        const manifestId = `${localhostUrl}/iiif/${manifestFile}`;
        const manifest = generateManifest(grouped, manifestId, manifestName, projectName, localhostUrl);
        
        // Write individual manifest
        const webManifestPath = `../web/iiif/${manifestFile}`;
        
        // Ensure the web/iiif directory exists
        const webIiifDir = '../web/iiif';
        if (!fs.existsSync(webIiifDir)) {
            fs.mkdirSync(webIiifDir, { recursive: true });
        }
        
        fs.writeFileSync(webManifestPath, JSON.stringify(manifest, null, 2));
        console.log(`✅ Wrote manifest to ${webManifestPath} (using localhost)`);
        console.log(`📋 Manifest includes ${Object.keys(grouped).length} canvases with annotations`);
        
        manifestFiles.push(manifestFile);
    }
    
    // Generate collection file using localhost only
    console.log(`\n📚 Generating collection for project: ${projectName}`);
    const localhostUrl = 'http://localhost:8080';
    const collection = generateCollection(manifestFiles, projectName, localhostUrl);
    const collectionFile = `${projectName}.json`;
    const collectionPath = `../web/iiif/${collectionFile}`;
    
    fs.writeFileSync(collectionPath, JSON.stringify(collection, null, 2));
    console.log(`✅ Wrote collection to ${collectionPath} (using localhost)`);
    console.log(`📋 Collection includes ${manifestFiles.length} manifest(s): ${manifestFiles.join(', ')}`);
    console.log(`🔍 Search service available at: ${localhostUrl}/annosearch/${projectName}/search`);
}

uploadAllAnnotations().catch(err => {
    console.error('Error uploading annotations:', err);
});
