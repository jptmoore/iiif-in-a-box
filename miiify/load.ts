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
            title: projectConfig.title || `${projectName} Collection`,
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
        title: `${projectName} Collection`,
        description: `Explore the ${projectName} collection`,
        metadata: [],
        provider: null
    };
}

function generateManifest(grouped: Record<string, Annotation[]>, manifestId: string, projectName: string = 'Project') {
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
                            id: `http://localhost:8080/cantaloupe/iiif/manifest/${imageId}/annotation`,
                            type: 'Annotation',
                            motivation: 'painting',
                            target: canvasUrl,
                            body: {
                                id: `http://localhost:8080/cantaloupe/iiif/3/${imageId}.tif/full/max/0/default.jpg`,
                                type: 'Image',
                                format: 'image/jpeg',
                                service: [
                                    {
                                        id: `http://localhost:8080/cantaloupe/iiif/3/${imageId}.tif/info.json`,
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
                    id: `http://localhost:8080/miiify/annotations/${containerId}/?page=0`,
                    type: 'AnnotationPage'
                }
            ]
        };
    });

    const manifest: any = {
        '@context': 'http://iiif.io/api/presentation/3/context.json',
        id: manifestId,
        type: 'Manifest',
        label: { en: [config.title] },
        summary: { en: [config.description] },
        service: [
            {
                id: `http://localhost:8080/annosearch/${projectName}/search`,
                type: 'SearchService2',
                service: [
                    {
                        id: `http://localhost:8080/annosearch/${projectName}/autocomplete`,
                        type: 'AutoCompleteService2'
                    }
                ]
            }
        ],
        items: canvases
    };

    // Add metadata if configured
    if (config.metadata && config.metadata.length > 0) {
        manifest.metadata = config.metadata;
    }

    // Add provider if configured
    if (config.provider) {
        manifest.provider = [config.provider];
    }

    return manifest;
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
    // Get command line arguments for project name, or use default
    const args = process.argv.slice(2);
    const projectName = args[0] || 'lincolnshire';
    
    console.log(`🎯 Loading annotations for project: ${projectName}`);
    
    // Find annotation files in web/annotations directory (simplified approach)
    let annotationData: any = null;
    let annotationFile = '';
    
    // Check in web/annotations directory (primary location)
    const webAnnotationsDir = '../web/annotations';
    if (fs.existsSync(webAnnotationsDir)) {
        // First try to find annotation file matching the project name
        const projectAnnotationFile = `${webAnnotationsDir}/${projectName}.json`;
        if (fs.existsSync(projectAnnotationFile)) {
            annotationFile = projectAnnotationFile;
            console.log(`📁 Found project annotation file: ${annotationFile}`);
        } else {
            // Fall back to first .json file found (with warning)
            const files = fs.readdirSync(webAnnotationsDir).filter(f => f.endsWith('.json'));
            if (files.length > 0) {
                annotationFile = `${webAnnotationsDir}/${files[0]}`;
                console.log(`⚠️  No annotation file found for project '${projectName}'`);
                console.log(`📁 Using first available file: ${annotationFile}`);
                console.log(`💡 Consider renaming to: ${webAnnotationsDir}/${projectName}.json`);
                if (files.length > 1) {
                    console.log(`📋 Other files available: ${files.slice(1).join(', ')}`);
                }
            }
        }
    }
    
    if (!annotationFile) {
        console.error('❌ No annotation files found in web/annotations/');
        console.error('📝 Please place your .json annotation files in web/annotations/');
        console.error('📝 Example: web/annotations/my-annotations.json');
        return;
    }
    
    const raw = fs.readFileSync(annotationFile, 'utf-8');
    const annotationPage = JSON.parse(raw);
    
    // Extract annotations from the AnnotationPage items array
    const annotations: Annotation[] = annotationPage.items || annotationPage;
    console.log(`📄 Loaded ${annotations.length} annotations from ${annotationFile}`);

    const grouped: Record<string, Annotation[]> = {};

    for (const anno of annotations) {
        const targets = Array.isArray(anno.target) ? anno.target : [anno.target];
        for (const t of targets) {
            const canvas = extractCanvasIdFromTarget(t);
            if (!grouped[canvas]) grouped[canvas] = [];
            grouped[canvas].push(anno);
        }
    }

    for (const [canvas, annos] of Object.entries(grouped)) {
        const containerId = extractContainerId(canvas);
        console.log(`\n📦 Processing container: ${containerId} (${annos.length} annotations)`);
        await ensureContainer(containerId);
        for (const anno of annos) {
            await ensureAnnotation(containerId, anno);
        }
    }

    // Write manifest to web/iiif directory (simplified approach)
    const manifestFile = `${projectName}.json`;
    const manifest = generateManifest(grouped, `http://localhost:8080/iiif/${manifestFile}`, projectName);
    
    // Always write to web/iiif directory - no complex path resolution needed
    const webManifestPath = `../web/iiif/${manifestFile}`;
    
    // Ensure the web/iiif directory exists
    const webIiifDir = '../web/iiif';
    if (!fs.existsSync(webIiifDir)) {
        fs.mkdirSync(webIiifDir, { recursive: true });
    }
    
    fs.writeFileSync(webManifestPath, JSON.stringify(manifest, null, 2));
    console.log(`\n✅ Wrote manifest to ${webManifestPath}`);
    console.log(`📋 Manifest includes ${Object.keys(grouped).length} canvases with annotations`);
}

uploadAllAnnotations().catch(err => {
    console.error('Error uploading annotations:', err);
});
