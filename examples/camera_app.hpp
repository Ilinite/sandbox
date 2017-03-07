#include "index.hpp"

struct ExperimentalApp : public GLFWApp
{
    uint64_t frameCount = 0;

    GlCamera camera;
    HosekProceduralSky skydome;
    RenderableGrid grid;
    FlyCameraController cameraController;
    Animator animator;
    
    std::vector<Renderable> proceduralModels;
    std::vector<Renderable> cameraPositions;
    
    std::unique_ptr<GlShader> simpleShader;
    
    std::vector<LightObject> lights;
    
    float cameraZ = 0.0f;
    float zeroOne = 0.0f;
    Pose start;
    Pose end;
    
    ExperimentalApp() : GLFWApp(940, 720, "GlCamera Sandbox App")
    {
        int width, height;
        glfwGetWindowSize(window, &width, &height);
        glViewport(0, 0, width, height);
        
        cameraController.set_camera(&camera);
        
        camera.look_at({0, 8, 24}, {0, 0, 0});
        cameraZ = camera.pose.position.z;
        
        simpleShader.reset(new GlShader(read_file_text("assets/shaders/simple_vert.glsl"), read_file_text("assets/shaders/simple_frag.glsl")));
        
        {
            lights.resize(2);
            lights[0].color = float3(249.f / 255.f, 228.f / 255.f, 157.f / 255.f);
            lights[0].pose.position = float3(25, 15, 0);
            lights[1].color = float3(255.f / 255.f, 242.f / 255.f, 254.f / 255.f);
            lights[1].pose.position = float3(-25, 15, 0);
        }
        
        {
            cameraPositions.resize(2);
            cameraPositions[0] = Renderable(make_frustum());
            cameraPositions[0].pose.position = float3(0, 8, +24);
            cameraPositions[0].mesh.set_non_indexed(GL_LINES);
            
            cameraPositions[1] = Renderable(make_frustum());
            cameraPositions[1].pose.position = float3(0, 8, -24);
            cameraPositions[1].mesh.set_non_indexed(GL_LINES);
        }
        
        {
            proceduralModels.resize(4);
            
            proceduralModels[0] = Renderable(make_sphere(1.0));
            proceduralModels[0].pose.position = float3(0, 2, +8);
            
            proceduralModels[1] = Renderable(make_cube());
            proceduralModels[1].pose.position = float3(0, 2, -8);
            
            proceduralModels[2] = Renderable(make_icosahedron());
            proceduralModels[2].pose.position = float3(8, 2, 0);
            
            proceduralModels[3] = Renderable(make_octohedron());
            proceduralModels[3].pose.position = float3(-8, 2, 0);
        }
        
        start = look_at_pose(float3(0, 8, +24), float3(-8, 2, 0));
        end = look_at_pose(float3(0, 8, -24), float3(-8, 2, 0));
        
        grid = RenderableGrid(1, 64, 64);
        
        gl_check_error(__FILE__, __LINE__);
    }
    
    void on_window_resize(int2 size) override
    {

    }
    
    void on_input(const InputEvent & event) override
    {
        if (event.type == InputEvent::KEY)
        {
            if (event.value[0] == GLFW_KEY_1 && event.action == GLFW_RELEASE)
                animator.make_tween(&cameraZ, -24.0f, 4.0f, Smoothstep::ease_in_out);
            if (event.value[0] == GLFW_KEY_2 && event.action == GLFW_RELEASE)
                animator.make_tween(&cameraZ, 24.0f, 2.0f, Smoothstep::ease_in_out);
            if (event.value[0] == GLFW_KEY_3 && event.action == GLFW_RELEASE)
                animator.make_tween(&zeroOne, 1.0f, 3.0f, Sine::ease_in_out);
            if (event.value[0] == GLFW_KEY_4 && event.action == GLFW_RELEASE)
                animator.make_tween(&zeroOne, 0.0f, 3.0f, Sine::ease_in_out);
        }
        cameraController.handle_input(event);
    }
    
    void on_update(const UpdateEvent & e) override
    {
        cameraController.update(e.timestep_ms);
        animator.update(e.timestep_ms);
        
        auto what = spherical(zeroOne * ANVIL_PI, zeroOne * ANVIL_PI / 2);
        
        float3 newPos = float3(what.x, 1, what.z) * float3(24, 8, 24);
        std::cout << newPos << std::endl;
        camera.set_position(float3(newPos.x, newPos.y, newPos.z));
        
        // Option One
        camera.look_at(camera.pose.position, {-8, 2, 0});
        
        // Option Two
        camera.pose.orientation = qlerp(start.orientation, end.orientation, zeroOne);
    }
    
    void on_draw() override
    {
        glfwMakeContextCurrent(window);
        
        glEnable(GL_CULL_FACE);
        glEnable(GL_DEPTH_TEST);

        int width, height;
        glfwGetWindowSize(window, &width, &height);
        glViewport(0, 0, width, height);
     
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glClearColor(0.1f, 0.1f, 0.5f, 1.0f);

        const auto proj = camera.get_projection_matrix((float) width / (float) height);
        const float4x4 view = camera.get_view_matrix();
        const float4x4 viewProj = mul(proj, view);
        
        skydome.render(viewProj, camera.get_eye_point(), camera.farClip);

        // Simple Shader
        {
            simpleShader->bind();
            
            simpleShader->uniform("u_viewProj", viewProj);
            simpleShader->uniform("u_eye", camera.get_eye_point());
            
            simpleShader->uniform("u_emissive", float3(.10f, 0.10f, 0.10f));
            simpleShader->uniform("u_diffuse", float3(0.4f, 0.4f, 0.4f));
            
            for (int i = 0; i < lights.size(); i++)
            {
                auto light = lights[i];
                
                simpleShader->uniform("u_lights[" + std::to_string(i) + "].position", light.pose.position);
                simpleShader->uniform("u_lights[" + std::to_string(i) + "].color", light.color);
            }
            
            for (const auto & model : proceduralModels)
            {
                simpleShader->uniform("u_modelMatrix", model.get_model());
                simpleShader->uniform("u_modelMatrixIT", inv(transpose(model.get_model())));
                model.draw();
            }
            
            for (const auto & model : cameraPositions)
            {
                simpleShader->uniform("u_modelMatrix", model.get_model());
                simpleShader->uniform("u_modelMatrixIT", inv(transpose(model.get_model())));
                model.draw();
            }
            gl_check_error(__FILE__, __LINE__);
            
            simpleShader->unbind();
        }
        
        grid.render(proj, view);

        gl_check_error(__FILE__, __LINE__);
        
        glfwSwapBuffers(window);
        
        frameCount++;
    }
    
};
