#include "v33.h"
#include "v33___024root.h"
#include "v33_V33.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include "imgui.h"
#include "imgui_impl_sdl2.h"
#include "imgui_impl_sdlrenderer2.h"
#include <stdio.h>
#include <SDL.h>

// TODO
// rom and ram regions - done
// rom loading - done
// vblank - done, rough
// comms
// display vram

VerilatedContext *contextp;
v33 *top;
VerilatedVcdC *tfp;

constexpr size_t MEM_SIZE = 0x100000;

uint8_t memory[MEM_SIZE];
uint32_t rom_mask;

constexpr uint32_t MT_ROM =       0x00000001;
constexpr uint32_t MT_WRITEABLE = 0x00000002;
constexpr uint32_t MT_WORKRAM =   0x00000004;
constexpr uint32_t MT_VRAM =      0x00000008;
constexpr uint32_t MT_PALRAM =    0x00000010;

uint32_t map_addr(uint32_t logical_addr, uint32_t *memtype)
{
    logical_addr = logical_addr & 0xfffff;
    if ((logical_addr & 0xf0000) == 0xa0000)
    {
        *memtype = MT_WRITEABLE | MT_WORKRAM;
        return logical_addr;
    }

    if ((logical_addr & 0xf0000) == 0xd0000)
    {
        *memtype = MT_WRITEABLE | MT_VRAM;
        return logical_addr;
    }

    if ((logical_addr & 0xf0000) == 0xe0000)
    {
        *memtype = MT_WRITEABLE | MT_PALRAM;
        return logical_addr & 0xe03ff;
    }

    *memtype = MT_ROM;
    return logical_addr & rom_mask;
}

uint16_t read_mem(uint32_t addr, bool ube)
{
    uint32_t memtype;
    uint32_t aligned_addr = map_addr(addr & ~1, &memtype);
    return memory[aligned_addr] | (memory[aligned_addr + 1] << 8);
}

void write_mem(uint32_t addr, bool ube, uint16_t dout)
{
    uint32_t memtype;
    addr = map_addr(addr, &memtype);
    if (memtype & MT_WRITEABLE)
    {
        if ((addr & 1) && ube)
        {
            memory[addr] = dout >> 8;
        }
        else if (((addr & 1) == 0) && !ube)
        {
            memory[addr] = dout & 0xff;
        }
        else
        {
            memory[addr] = dout & 0xff;
            memory[addr + 1] = dout >> 8;
        }
    }
}

uint16_t prev_state = 0x0000;
void print_trace(const v33_V33 *cpu)
{
    static bool skip = false; //true; // skip the first output because mame does
    if( cpu->state == 0 && cpu->state != prev_state)
    {
        if (!skip)
        {
            printf("psw=%04X aw=%04X cw=%04X dw=%04X bw=%04X sp=%04X bp=%04X ix=%04X iy=%04X ds1=%04X ps=%04X ss=%04X ds0=%04X %05X\n",
                    cpu->reg_psw,
                    cpu->reg_aw,
                    cpu->reg_cw,
                    cpu->reg_dw,
                    cpu->reg_bw,
                    cpu->reg_sp,
                    cpu->reg_bp,
                    cpu->reg_ix,
                    cpu->reg_iy,
                    cpu->reg_ds1,
                    cpu->reg_ps,
                    cpu->reg_ss,
                    cpu->reg_ds0,
                    (cpu->reg_ps << 4) + cpu->next_pc
                  );
        }
        skip = false;
    }
    prev_state = cpu->state;
}

uint32_t total_ticks = 0;

void tick(int count = 1)
{
    for( int i = 0; i < count; i++ )
    {
        total_ticks++;

        if (~top->n_mreq)
        {
            if (top->r_w && ~top->n_mstb)
            {
                top->din = read_mem(top->addr, (~top->n_ube) & 1);
            }
            else
            {
                top->din = 0xffff;
            }

            if (!top->r_w && ~top->n_mstb)
            {
                write_mem(top->addr, (~top->n_ube) & 1, top->dout);
            }
        }

        contextp->timeInc(1);
        top->clk = 0;

        top->eval();
        tfp->dump(contextp->time());
        //print_trace(top->rootp->V33);

        contextp->timeInc(1);
        top->clk = 1;

        top->eval();
        tfp->dump(contextp->time());
        //print_trace(top->rootp->V33);
    }
}

SDL_Window *sdl_window;
SDL_Renderer *sdl_renderer;

bool imgui_init()
{
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER | SDL_INIT_GAMECONTROLLER) != 0)
    {
        printf("Error: %s\n", SDL_GetError());
        return false;
    }

    // Create window with SDL_Renderer graphics context
    SDL_WindowFlags window_flags = (SDL_WindowFlags)(SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    SDL_Window* window = SDL_CreateWindow("IREM", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 1280, 720, window_flags);
    if (window == nullptr)
    {
        printf("Error: SDL_CreateWindow(): %s\n", SDL_GetError());
        return false;
    }

    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_PRESENTVSYNC | SDL_RENDERER_ACCELERATED);
    if (renderer == nullptr)
    {
        SDL_Log("Error creating SDL_Renderer!");
        return false;
    }
    //SDL_RendererInfo info;
    //SDL_GetRendererInfo(renderer, &info);
    //SDL_Log("Current SDL_Renderer: %s", info.name);

    // Setup Dear ImGui context
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls

    // Setup Dear ImGui style
    ImGui::StyleColorsDark();
    //ImGui::StyleColorsLight();

    // Setup Platform/Renderer backends
    ImGui_ImplSDL2_InitForSDLRenderer(window, renderer);
    ImGui_ImplSDLRenderer2_Init(renderer);

    sdl_window = window;
    sdl_renderer = renderer;

    return true;
}

void imgui_frame()
{
    bool done = false;

    SDL_Event event;
    while (SDL_PollEvent(&event))
    {
        ImGui_ImplSDL2_ProcessEvent(&event);
        if (event.type == SDL_QUIT)
            done = true;
        if (event.type == SDL_WINDOWEVENT && event.window.event == SDL_WINDOWEVENT_CLOSE && event.window.windowID == SDL_GetWindowID(sdl_window))
            done = true;
    }

    ImGui_ImplSDLRenderer2_NewFrame();
    ImGui_ImplSDL2_NewFrame();
    ImGui::NewFrame();

    ImGui::Begin("Hello, world!");                          // Create a window called "Hello, world!" and append into it.

    uint8_t *vram = &memory[0xd8000];
    char line[48];
    for( int y = 0; y < 28; y++ )
    {
        uint8_t *vram = memory + 0xd8000 + (y * 256);
        for( int x = 0; x < 40; x++ )
        {
            if( *vram < 0x20 )
                line[x] = ' ';
            else
                line[x] = *vram;
            vram += 4;
        }
        line[40] = '\0';
        ImGui::Text("%s", line);
    }
        
    ImGui::End();


    ImGui::Render();

    ImGuiIO& io = ImGui::GetIO();
    SDL_RenderSetScale(sdl_renderer, io.DisplayFramebufferScale.x, io.DisplayFramebufferScale.y);
    SDL_SetRenderDrawColor(sdl_renderer, 0, 0, 0, 0);
    SDL_RenderClear(sdl_renderer);
    ImGui_ImplSDLRenderer2_RenderDrawData(ImGui::GetDrawData(), sdl_renderer);
    SDL_RenderPresent(sdl_renderer);
}

int main(int argc, char **argv)
{
    if( !imgui_init() )
    {
        return -1;
    }

    if (argc != 2)
    {
        printf( "Usage: %s BIN_FILE\n", argv[0] );
        return -1;
    }

    FILE *fp = fopen( argv[1], "rb" );
    if (fp == nullptr)
    {
        printf( "Could not open %s\n", argv[1] );
        return -1;
    }

    fseek(fp, 0, SEEK_END);
    int file_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    fread(memory, 1, file_size, fp);
    fclose(fp);

    rom_mask = file_size - 1;
    printf("ROM Size: %d (0x%06x)\n", file_size, rom_mask);

    contextp = new VerilatedContext;
    top = new v33{contextp};

    Verilated::traceEverOn(true);
    tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("test_186.vcd");

    top->ce = 1;
    top->ready = 1;

    top->n_reset = 0;
    tick(10);
    top->n_reset = 1;
    tick(1);

    for( int i = 0; i < 2; i++ )
    {
        top->rootp->V33->reg_ps = 0xf000;
        top->rootp->V33->next_pc = 0xfff0;
        top->rootp->V33->set_pc = 1;
        tick(1);
    }
    
    top->rootp->V33->set_pc = 0;

    bool vblank = false;
    
    for( int x = 0; x < 10000000; x++ )
    //while(true)
    {
        uint32_t frame_ticks = total_ticks % 260000;
        if (frame_ticks < 10000)
        {
            top->n_intp0 = 1;
            if (!vblank)
            {
                imgui_frame();
            }
            vblank = true;
        }
        else
        {
            top->n_intp0 = 0;
            vblank = false;
        }

        tick(1);
        if (top->rootp->V33->halt) break;
    }

    top->final();
    tfp->close();

    fp = fopen("vram.bin", "wb");
    fwrite(&memory[0xd0000], 1, 64 * 1024, fp);
    fclose(fp);
    
    delete top;
    delete contextp;
    return 0;
}
