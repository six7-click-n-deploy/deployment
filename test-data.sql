-- ================================================================
-- Test Data for Simple App Deployment
-- ================================================================
-- This script creates a test user, app, and deployment for testing
-- the worker deployment system with the simple-app repository

-- ----------------------------------------------------------------
-- 1. Create Test User
-- ----------------------------------------------------------------
INSERT INTO users (
    "userId",
    email,
    username,
    password,
    role,
    "courseId",
    created_at
) VALUES (
    gen_random_uuid(),
    'test@example.com',
    'testuser',
    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5ufmJ5zKnYWjW', -- password: "test123"
    'STUDENT',
    NULL,
    NOW()
) ON CONFLICT (email) DO NOTHING
RETURNING "userId";

-- ----------------------------------------------------------------
-- 2. Create Simple App and Deployment
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_user_id UUID;
    v_app_id UUID;
    v_deployment_id UUID;
BEGIN
    -- Get user ID
    SELECT "userId" INTO v_user_id FROM users WHERE email = 'test@example.com';
    
    -- Create Simple App
    INSERT INTO apps (
        "appId",
        name,
        description,
        image,
        git_link,
        "userId",
        created_at
    ) VALUES (
        gen_random_uuid(),
        'Simple Web Server',
        'A simple nginx web server deployed on OpenStack using Terraform and Packer',
        NULL,
        'git@github.com:six7-click-n-deploy/simple-app.git',
        v_user_id,
        NOW()
    ) ON CONFLICT DO NOTHING
    RETURNING "appId" INTO v_app_id;
    
    -- If app already exists, get its ID
    IF v_app_id IS NULL THEN
        SELECT "appId" INTO v_app_id FROM apps WHERE git_link = 'git@github.com:six7-click-n-deploy/simple-app.git';
    END IF;
    
    -- Create deployment
    INSERT INTO deployments (
        "deploymentId",
        name,
        status,
        "commitHash",
        "commitInfo",
        "userInputVar",
        "userId",
        "appId"
    ) VALUES (
        gen_random_uuid(),
        'Simple Web Server - Test Deployment',
        'PENDING',
        NULL, -- Will be set by worker
        NULL, -- Will be set by worker
        '{"instance_name": "test-webserver", "flavor": "gp1.small", "image_name": "Ubuntu 22.04", "key_pair": "", "environment": "test", "floating_ip_pool": "NAT", "network_name": "4971e080-966d-485e-a161-3e2b7fefad53"}',
        v_user_id,
        v_app_id
    )
    RETURNING "deploymentId" INTO v_deployment_id;
    
    -- Show created IDs
    RAISE NOTICE 'User ID: %', v_user_id;
    RAISE NOTICE 'App ID: %', v_app_id;
    RAISE NOTICE 'Deployment ID: %', v_deployment_id;
    RAISE NOTICE '';
    RAISE NOTICE 'Test data created successfully!';
    RAISE NOTICE 'Login with: username=testuser, password=test123';
END $$;

-- ----------------------------------------------------------------
-- 4. Verify Created Data
-- ----------------------------------------------------------------
SELECT 
    u.username,
    a.name as app_name,
    a.git_link,
    d.name as deployment_name,
    d.status,
    d."deploymentId"
FROM deployments d
JOIN users u ON d."userId" = u."userId"
JOIN apps a ON d."appId" = a."appId"
WHERE u.email = 'test@example.com'
ORDER BY d."deploymentId" DESC
LIMIT 1;
