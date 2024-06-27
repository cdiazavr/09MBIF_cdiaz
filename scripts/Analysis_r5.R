
# Libraries ---------------------------------------------------------------

library(tidyverse)    # structured data manipulation and visualization
library(magrittr)     # Additional tools for data manipulation
library(paletteer)    # Additional color palettes for plots
library(latex2exp)    # LaTeX expressions in plots
library(ggrepel)      # Labels that automatically avoid collisions
library(scales)       # Scale functions for visualizations
library(gglm)         # Plots for linear regression diagnostics
library(jtools)       # Additional summaries of linear models
library(equatiomatic) # Extracts equations of linear models as LaTeX equations
library(pracma)       # Numerical analysis (numerical integration is used)
library(ggbeeswarm)   # Swarm plots


# Housekeeping ------------------------------------------------------------

setwd("~/Documents/Benchmark/AnalysisR/Data/")

## Proteins
proteins <- c(
  "P_mainly_alpha_1_1cdl",  # protein[1]
  "P_mainly_alpha_2_101m",  # protein[2]
  "P_mainly_alpha_3_1e7f",  # protein[3]
  "P_mainly_alpha_4_3i5f",  # protein[4]
  "P_mainly_beta_1_1csp",   # protein[5]
  "P_mainly_beta_2_1a3y",   # protein[6]
  "P_mainly_beta_3_1a2v",   # protein[7]
  "P_mainly_beta_4_3wm5",   # protein[8]
  "P_alpha_beta_1_1acb",    # protein[9]
  "P_alpha_beta_2_1a6j",    # protein[10]
  "P_alpha_beta_3_1a5k",    # protein[11]
  "P_alpha_beta_4_2vdo",    # protein[12]
  "P_few_SSpred_1_2mps",     # protein[13]
  "P_few_SSpred_2_1bg5",    # protein[14]
  "P_few_SSpred_3_4giq",    # protein[15]
  "P_few_SSpred_4_5j7t"     # protein[16]
)

## Flags tested
flags <- c(
  'nb=auto pme=auto pmefft=auto bonded=auto update=auto', #flag[1]
  'nb=cpu pme=cpu pmefft=cpu bonded=cpu update=cpu',      #flag[2]
  'nb=gpu pme=cpu pmefft=cpu bonded=cpu update=cpu',      #flag[3]
  'nb=gpu pme=cpu pmefft=cpu bonded=cpu update=gpu',      #flag[4]
  'nb=gpu pme=cpu pmefft=cpu bonded=gpu update=cpu',      #flag[5]
  'nb=gpu pme=cpu pmefft=cpu bonded=gpu update=gpu',      #flag[6]
  'nb=gpu pme=gpu pmefft=cpu bonded=cpu update=cpu',      #flag[7]
  'nb=gpu pme=gpu pmefft=cpu bonded=cpu update=gpu',      #flag[8]
  'nb=gpu pme=gpu pmefft=cpu bonded=gpu update=cpu',      #flag[9]
  'nb=gpu pme=gpu pmefft=cpu bonded=gpu update=gpu',      #flag[10]
  'nb=gpu pme=gpu pmefft=gpu bonded=cpu update=cpu',      #flag[11]
  'nb=gpu pme=gpu pmefft=gpu bonded=cpu update=gpu',      #flag[12]
  'nb=gpu pme=gpu pmefft=gpu bonded=gpu update=cpu',      #flag[13]
  'nb=gpu pme=gpu pmefft=gpu bonded=gpu update=gpu'       #flag[14]
)

## Systems' sizes (number of atoms)
system_info <- tibble(
  Protein_name = proteins,
  Atoms = c(12171,
            24522,
            100612,
            200786,
            12306,
            23979,
            107859,
            169505,
            11428,
            20340,
            74614,
            194550,
            18467,
            33156,
            130997,
            234179),
  Protein_structure = c(rep("A) Alfa", 4),
                        rep("B) Beta", 4),
                        rep("C) Alfa y beta", 4),
                        rep("D) Pocas SSpred", 4)
                        )
)

## Custom plot theme
panel_dark_color <- "gray20"

custom_theme <- theme_light() + theme(
  axis.text = element_text(color = "black", size = 8),
  axis.title = element_text(size = 9, face = "plain"),
  axis.ticks = element_line(linewidth = 0.5, color = panel_dark_color),
  legend.title = element_text(size = 9, face = "bold"),
  legend.text = element_text(size = 8),
  panel.border = element_rect(color = panel_dark_color),
  strip.text = element_text(color = "black", face = "bold", hjust = 0, size = 9),
  strip.background = element_rect(colour = "white", fill = "white"),
  plot.caption = element_text(hjust = 0)
)

## Custom function for rounding numbers with different significant digits
smart_round <- function(x) {
  if(abs(x)<1)         {return(signif(x, digits = 2))}
  if(abs(x)>=1 & x<10) {return(signif(x, digits = 2))}
  if(abs(x)>=10)       {return(round(x, digits = 0))}
}

## Use 3 decimal places for seconds
options(digits.secs=3)
## Use 15 significant figures
options(digits = 15) 

## Function to convert axis labels from format "1e1" to "1 x 10^1"
scientific <- function(x){
  ifelse(x==0, "0", parse(text=gsub("[+]", "", gsub("e", "%*%10^", scientific_format()(x)))))
}

# Strong scaling | Data import --------------------------------------------

## Load and process data
strong_scaling_data <- tibble()

for (protein in proteins) {
  strong_scaling_data %<>% bind_rows(
    read.delim(file.path(protein, "strong_scaling_test/benchmark_mdrun.tsv"))
  )
}

replicates <- strong_scaling_data %>% select(Replicate) %>% n_distinct()

strong_scaling_data %<>% 
  left_join(system_info, by = "Protein_name") %>% 
  mutate(CPU_cores = round(CPU_usage_pct/100)) %>% 
  mutate(ns.day_1e4atoms = ns.day/(Atoms/10000)) %>% 
  select(Protein_name, Protein_structure, Atoms, Replicate, CPU_cores, ns.day_1e4atoms) %>%
  group_by(Protein_name, Protein_structure, Atoms, CPU_cores) %>%
  summarise(ns.day_1e4atoms_AVG = mean(ns.day_1e4atoms),
            ns.day_1e4atoms_SD = sd(ns.day_1e4atoms),
            ns.day_1e4atoms_SE = sd(ns.day_1e4atoms)/sqrt(replicates),
            ns.day_1e4atoms_CV = sd(ns.day_1e4atoms)/mean(ns.day_1e4atoms)
            ) %>% ungroup() %>%
  select(-Protein_name)

## Scale the number of atoms into a relative and discrete size
smallest_system <- strong_scaling_data$Atoms %>% min()
biggest_system <- strong_scaling_data$Atoms %>% max()


strong_scaling_data %<>%
  mutate(Relative_size = Atoms/smallest_system) %>% 
  arrange(Relative_size)

rm(protein, replicates)


# Strong scaling | Plots --------------------------------------------------

## Plot strong scaling
### By secondary structure
plot_strong_scaling_bySS <- 
  ggplot(data = strong_scaling_data,
         mapping = aes(x = CPU_cores,
                       y = ns.day_1e4atoms_AVG,
                       color = log10(Relative_size),
                       group = Atoms,
                       )
         ) +
  # geom_step(direction = "hv") +
  geom_point(shape = 15, 
             size =  1.5) +
  geom_line(linewidth = 0.15,
            linetype = "solid",
            alpha = 1) +
  # geom_errorbar(mapping = aes(ymin = ns.day_1e4atoms_AVG-ns.day_1e4atoms_SE,
  #                             ymax = ns.day_1e4atoms_AVG+ns.day_1e4atoms_SE,
  #                             ),
  #               width = .1,
  #               linewidth = .5,
  #               ) +
  geom_label(data = strong_scaling_data %>% filter(CPU_cores==18),
             aes(x = CPU_cores,
                 y = ns.day_1e4atoms_AVG,
                 color = log10(Relative_size),
                 group = Atoms,
                 label = paste(Atoms, "átomos")
                 ),
             hjust = 1,
             size = 2.75,
             nudge_y = 0.2,
             label.padding = unit(0.13, "lines")
             ) +
  scale_color_paletteer_c(name = "Tamaño relativo del\nsistema (log10)",
                          "ggthemes::Classic Red-Black",
                          direction = -1,
                          breaks = seq(0,1.50,.25),
                          )  +
  scale_y_continuous(trans = "log10",
                     name = latex2exp::TeX(r'($Desempeño\,\left( \frac{ns/día}{10^4\,átomos} \right)$)'),
                     breaks = c(0.1, 1, 10, 100),
                     labels = c("0.1", "1", "10", "100"),
                     minor_breaks = c(
                       seq(.1,1,.1), seq(1,10,1), seq(10,100,10)
                       ),
                     ) +
  scale_x_continuous(name = "Hilos de procesamiento",
                     breaks = c(1,6,12,18),
                     minor_breaks = seq(1,18,1),
                     expand = c(0.02,0)
                     ) +
  facet_wrap(.~Protein_structure) +
  custom_theme +
  labs(
    caption = "* Cada punto corresponde a la media aritmética de 5 réplicas."
  ) +
  theme(
    legend.position = "none",
    legend.key.height = unit(8, 'mm'),
  )


### By system size
### Put together all data, regardless of secondary structure
strong_scaling_data_no_SS <- 
  strong_scaling_data %>% 
  select(Atoms, CPU_cores, ns.day_1e4atoms_AVG) %>% 
  group_by(CPU_cores) %>% 
  mutate(max_AVG = max(ns.day_1e4atoms_AVG)) %>% 
  ungroup()


plot_strong_scaling_byAtoms <- 
  ggplot(data = strong_scaling_data_no_SS,
       aes(x = Atoms,
           y = ns.day_1e4atoms_AVG,
           color = max_AVG,
           group = CPU_cores,
           )
       ) +
  # geom_line() +
  # geom_step(direction = "hv") +
  geom_smooth(se = FALSE, linewidth = .5, method = "gam") +
  scale_color_paletteer_c(name = latex2exp::TeX(r'($Máximo\ desempeño\ observado\,\left( \frac{ns/día}{10^4\,átomos} \right)$)'),
                          "grDevices::Zissou 1",
                          # "viridis::turbo",
                          direction = -1,
                          ) +
  geom_label(data = strong_scaling_data_no_SS %>% filter(Atoms==smallest_system  & CPU_cores %in% c(1,6,7,12,18,13)),
             aes(x = Atoms,
                 y = ns.day_1e4atoms_AVG,
                 color = max_AVG,
                 group = CPU_cores,
                 label = paste(CPU_cores, "hilos")
                 ),
             hjust = 1,
             nudge_y = 2,
             size = 2.75,
             label.padding = unit(0.1, "lines"),
             ) +
  scale_x_continuous(name = "Tamaño del sistema (número de átomos)",
                     trans = "log10",
                     limits = c(0.9e4, 2.5e5),
                     labels = scientific,
                     breaks = c(1e4, 1e5, 2e5),
                     minor_breaks = c(
                       seq(1e4,1e5,1e4)
                       ),
                     expand = c(0,0.01)
                     ) +
  scale_y_continuous(name = latex2exp::TeX(r'($Desempeño\,\left( \frac{ns/día}{10^4\,átomos} \right)$)'),
                     limits = c(0, 170),
                     breaks = seq(0, 160, 20),
                     minor_breaks = seq(0, 170, 10),
                     ) +
  custom_theme +
  theme(
    legend.position = c(1, 1),
    legend.justification = c(1, 1),
    legend.title = element_text(size=8),
    legend.key.width = unit(10, 'mm'),
    legend.direction = "horizontal",
    legend.background = element_blank()
  )




# Energy consumption | Data import ----------------------------------------

## Global performance logged by GROMACS
global_performance <- tibble()

for (protein in proteins) {
  for (flag in flags) {
    global_performance %<>% bind_rows(
      read.delim(file.path(protein, flag, "benchmark_mdrun.tsv")) %>% mutate(Flag = flag)
    )
  }
}

replicates <- global_performance %>% select(Replicate) %>% n_distinct()

global_performance %<>% 
  left_join(system_info, by = "Protein_name") %>% 
  mutate(Protein_structure = parse_factor(Protein_structure,
                                          ordered = TRUE,
                                          levels = c("A) Alfa",
                                                     "B) Beta",
                                                     "C) Alfa y beta",
                                                     "D) Pocas SSpred")
                                          ),
         Flag = parse_factor(Flag),
         Replicate = parse_factor(as.character(Replicate))
         ) %>% 
  mutate(ns.day_1e4atoms = ns.day/(Atoms/10000)) %>% 
  select(Protein_name, Protein_structure, Atoms, Flag, Replicate, ns.day_1e4atoms) %>% 
  select(-Protein_name) %>% 
  arrange(Protein_structure)

rm(protein, flag, replicates)


## CPU logged data
cpu_energy <- tibble()

for (protein in proteins) {
  for (flag in flags) {
    cpu_energy %<>% bind_rows(
      read.delim(file.path(protein, flag, "benchmark_cpu.tsv")) %>% mutate(Protein_name = protein, Flag = flag)
    )
  }
}

cpu_energy %<>% 
  filter(Parameter == "package_power") %>% 
  left_join(system_info, by = "Protein_name") %>%
  mutate(Date_time = ymd_hms(Date_time)) %>% 
  mutate(Date_time_numeric = as.numeric(Date_time)) %>% 
  select(Protein_structure, Atoms, Flag, Replicate, Date_time_numeric, Meassure) %>% 
  group_by(Protein_structure, Atoms, Flag, Replicate) %>% 
  summarise(CPU_energy_integral_J = trapz(Date_time_numeric, Meassure),
            ) %>% 
  ungroup() %>% 
  mutate(Protein_structure = parse_factor(Protein_structure,
                                          ordered = TRUE,
                                          levels = c("A) Alfa",
                                                     "B) Beta",
                                                     "C) Alfa y beta",
                                                     "D) Pocas SSpred")
                                          ),
         Flag = parse_factor(Flag),
         Replicate = parse_factor(as.character(Replicate))
         )

rm(protein, flag)


## GPU logged data

gpu_energy <- tibble()

for (protein in proteins) {
  for (flag in flags) {
    gpu_energy %<>% bind_rows(
      read.delim(file.path(protein, flag, "benchmark_gpu.tsv")) %>% mutate(Protein_name = protein, Flag = flag)
    )
  }
}

gpu_energy %<>% 
  filter(Parameter == "package_power") %>% 
  left_join(system_info, by = "Protein_name") %>%
  mutate(Date_time = ymd_hms(Date_time)) %>% 
  mutate(Date_time_numeric = as.numeric(Date_time)) %>% 
  select(Protein_structure, Atoms, Flag, Replicate, Date_time_numeric, Meassure) %>% 
  group_by(Protein_structure, Atoms, Flag, Replicate) %>% 
  summarise(GPU_energy_integral_J = trapz(Date_time_numeric, Meassure)
            ) %>% 
  ungroup() %>% 
  mutate(Protein_structure = parse_factor(Protein_structure,
                                          ordered = TRUE,
                                          levels = c("A) Alfa",
                                                     "B) Beta",
                                                     "C) Alfa y beta",
                                                     "D) Pocas SSpred")
  ),
  Flag = parse_factor(Flag),
  Replicate = parse_factor(as.character(Replicate))
  )

rm(protein, flag)


## Integrate global performance with CPU and GPU power data

global_performance %<>% 
  left_join(cpu_energy, by = c("Protein_structure","Atoms","Flag","Replicate")) %>% 
  left_join(gpu_energy, by = c("Protein_structure","Atoms","Flag","Replicate")) %>% 
  group_by(Protein_structure, Atoms, Flag) %>% 
  summarise(
    ns.day_1e4atoms_AVG = mean(ns.day_1e4atoms),
    ns.day_1e4atoms_SE  = sd(ns.day_1e4atoms)/sqrt(n()),
    CPU_energy_J_AVG    = mean(CPU_energy_integral_J),
    CPU_energy_J_SE     = sd(CPU_energy_integral_J)/sqrt(n()),
    GPU_energy_J_AVG    = mean(GPU_energy_integral_J),
    GPU_energy_J_SE     = sd(GPU_energy_integral_J)/sqrt(n()),
    ) %>% 
  ungroup() %>% 
  mutate(Total_energy_J = CPU_energy_J_AVG + GPU_energy_J_AVG,
         Relative_size = Atoms/smallest_system)

rm(cpu_energy, gpu_energy)




# Energy consumption | Plots ----------------------------------------------

energy_consumption <- 
  global_performance %>% 
  select(Protein_structure,
         Atoms,
         Relative_size,
         Flag,
         ns.day_1e4atoms_AVG,
         CPU_energy_J_AVG,
         GPU_energy_J_AVG,
         Total_energy_J
         ) %>% 
  pivot_longer(cols = c("CPU_energy_J_AVG", "GPU_energy_J_AVG"),
               names_to = "Device",
               values_to = "Energy_J") %>% 
  mutate(Device = str_replace(Device, "CPU_energy_J_AVG", "CPU")) %>% 
  mutate(Device = str_replace(Device, "GPU_energy_J_AVG", "GPU")) %>% 
  mutate(Device = parse_factor(Device),
         ns.day_1e4atoms_AVG_round = sapply(ns.day_1e4atoms_AVG, smart_round)
         )


CPU_GPU_colors <- c("CPU" = "#F5191C", "GPU" = "#557CCA")


## Energy consumptions vs. Atoms

plot_energy_consumption_byAtoms <- 
  ggplot() +
  geom_area(data = energy_consumption %>% 
              mutate(Flag = str_replace_all(Flag, ' ', '\n')),
            aes(x = Atoms,
                y = Energy_J/1000,
                fill = Device),
            color = panel_dark_color,
            alpha = 1) +
  geom_label_repel(data = energy_consumption %>% 
                     filter(Device == "CPU") %>% 
                     mutate(Flag = str_replace_all(Flag, ' ', '\n')),
                   aes(x = Atoms,
                       y = Total_energy_J/1000,
                       label = ns.day_1e4atoms_AVG_round
                       ),
                   label.padding = unit(0.1, "lines"),
                   size = 2.5,
                   nudge_y = 1,
                   segment.size = 0.3,
                   color = "gray40",
                   direction = "both",
                   max.overlaps = 7,
                   max.iter = 1e5,
                   ) +
  facet_wrap(. ~ Flag, ncol = 3) +
  geom_text(data = energy_consumption %>% 
              mutate(label_posX = smallest_system, label_posY=105) %>% 
              select(Flag, label_posX, label_posY) %>% 
              unique() %>% 
              mutate(Flag = str_replace_all(Flag, ' ', '\n')),
            aes(label = Flag,
                x = label_posX,
                y = label_posY
                ),
            size = 2.6,
            hjust = 0, vjust = 1,
            nudge_x = 0.025, nudge_y = -2.5,
            lineheight = 0.8,
            color = panel_dark_color,
            
            ) +
  scale_x_continuous(name = "Tamaño del sistema (número de átomos)",
                     trans = "log10",
                     limits = c(smallest_system, biggest_system),
                     labels = scientific,
                     breaks = c(1.2e4, 1e5),
                     minor_breaks = c(
                       seq(1e4,1e5,1e4), seq(1e5,1e6,1e5)
                       ),
                     expand = c(0,0)
                     ) +
  scale_y_continuous(name = "Energía consumida (kJ)",
                     trans = "identity",
                     limits = c(0,105),
                     breaks = seq(0, 100, 20),
                     minor_breaks = seq(0, 100, 10),
                     expand = c(0,0)
                     ) +
  scale_fill_manual(values = CPU_GPU_colors,
                    name = "Unidad de\nprocesamiento") +
  custom_theme +
  theme(
    legend.position = c(5/6, 1/10),
    panel.spacing = unit(1, "lines"),
    strip.background = element_blank(),
    strip.text = element_blank(),
    axis.title = element_text(face = "bold"),
    axis.text.x = element_text(hjust = 0.1),
    panel.spacing.x = unit(1.5, "mm"),
    panel.spacing.y = unit(1.5, "mm"),
  ) +
  labs(caption = latex2exp::TeX(r'(*Los valores en el interior de los gráficos muestran el desempeño en algunos sistemas selectos, en unidades $\frac{ns/día}{10^4\,átomos}$)'))


### Zoom into best performers

plot_energy_consumption_byAtoms_bests <- 
  ggplot() +
  geom_area(data = energy_consumption %>% 
              filter(Flag %in% c("nb=auto pme=auto pmefft=auto bonded=auto update=auto",
                                 "nb=gpu pme=gpu pmefft=gpu bonded=cpu update=gpu",
                                 "nb=gpu pme=gpu pmefft=gpu bonded=gpu update=gpu")) %>% 
              mutate(Flag = str_replace_all(Flag, ' ', '\n')),
            aes(x = Atoms,
                y = Energy_J/1000,
                fill = Device),
            color = panel_dark_color,
            alpha = 1
            ) +
  geom_label_repel(data = energy_consumption %>% 
                     filter(Device == "CPU") %>% 
                     filter(Flag %in% c("nb=auto pme=auto pmefft=auto bonded=auto update=auto",
                                        "nb=gpu pme=gpu pmefft=gpu bonded=cpu update=gpu",
                                        "nb=gpu pme=gpu pmefft=gpu bonded=gpu update=gpu" )) %>%
                     mutate(Flag = str_replace_all(Flag, ' ', '\n')),
                   aes(x = Atoms,
                       y = Total_energy_J/1000,
                       label = ns.day_1e4atoms_AVG_round
                       ),
                   label.padding = unit(0.1, "lines"),
                   size = 2.5,
                   nudge_y = 1,
                   segment.size = 0.3,
                   color = "gray40",
                   direction = "both",
                   max.overlaps = 7,
                   max.iter = 1e5,
                   ) +
  facet_wrap(. ~ Flag, ncol = 3) +
  geom_text(data = energy_consumption %>%
              filter(Flag %in% c("nb=auto pme=auto pmefft=auto bonded=auto update=auto",
                                 "nb=gpu pme=gpu pmefft=gpu bonded=cpu update=gpu",
                                 "nb=gpu pme=gpu pmefft=gpu bonded=gpu update=gpu" )) %>% 
              mutate(label_posX = smallest_system, label_posY=16) %>% 
              select(Flag, label_posX, label_posY) %>% 
              unique() %>% 
              mutate(Flag = str_replace_all(Flag, ' ', '\n')),
            aes(label = Flag,
                x = label_posX,
                y = label_posY
            ),
            size = 2.6,
            hjust = 0, vjust = 1,
            nudge_x = 0.025, nudge_y = -0.25,
            lineheight = 0.8,
            color = panel_dark_color,
            
  ) +
  scale_x_continuous(name = "Tamaño del sistema (número de átomos)",
                     trans = "log10",
                     limits = c(smallest_system, biggest_system),
                     labels = scientific,
                     breaks = c(1.2e4, 1e5),
                     minor_breaks = c(
                       seq(1e4,1e5,1e4), seq(1e5,1e6,1e5)
                     ),
                     expand = c(0,0)
  ) +
  scale_y_continuous(name = "Energía consumida (kJ)",
                     trans = "identity",
                     limits = c(0,16),
                     breaks = seq(0, 15, 5),
                     minor_breaks = seq(0, 20, 1),
                     expand = c(0,0)
  ) +
  scale_fill_manual(values = CPU_GPU_colors,
                    name = "Unidad de\nprocesamiento") +
  custom_theme +
  theme(
    legend.position = "right",
    panel.spacing = unit(1, "lines"),
    strip.background = element_blank(),
    strip.text = element_blank(),
    axis.title = element_text(face = "bold"),
    axis.text.x = element_text(hjust = 0.1),
    panel.spacing.x = unit(1.5, "mm"),
    panel.spacing.y = unit(1.5, "mm"),
  ) +
  labs(caption = latex2exp::TeX(r'(*Los valores en el interior de los gráficos muestran el desempeño en algunos sistemas selectos, en unidades $\frac{ns/día}{10^4\,átomos}$)'))



## Energy consumption dependency on performance

global_performance_no_SS <- 
  global_performance %>% 
  select(Atoms, Flag, ns.day_1e4atoms_AVG, Total_energy_J) %>% 
  group_by(Flag) %>% 
  mutate(ns.day_1e4atoms_MAX = max(ns.day_1e4atoms_AVG)) %>% 
  ungroup()


plot_energy_consumption_vs_performance <-
  ggplot(data = global_performance_no_SS,
       aes(x = ns.day_1e4atoms_AVG,
           y = Total_energy_J/1000,
           color = ns.day_1e4atoms_MAX,
           )
       ) +
  geom_line(linewidth = 0.5) +
  geom_point(size = 2,
             ) +
  scale_color_paletteer_c("ggthemes::Red-Green-Gold Diverging",
                          direction = 1,
                          breaks = seq(100,600,100),
                          name = latex2exp::TeX(r'($Máximo\ desempeño\ observado\,\left( \frac{ns/día}{10^4\,átomos} \right)$)')
                          ) +
  facet_wrap(. ~ Flag, ncol = 3) +
  scale_y_continuous(name = "Energía consumida (kJ)",
                     limits = c(0,100),
                     breaks = seq(0, 100, 20),
                     ) +
  scale_x_continuous(trans = "log10",
                     name = latex2exp::TeX(r'($Desempeño\,\left( \frac{ns/día}{10^4\,átomos} \right)$)'),
                     breaks = c(0.1, 1, 10, 100),
                     labels = c("0.1", "1", "10", "100"),
                     minor_breaks = c(seq(.1,1,.1), seq(1,10,1), seq(10,100,10)),
                     ) +
  custom_theme +
  theme(
    legend.position = c(5/6, 1/10),
    strip.text = element_text(color = panel_dark_color, face = "bold", hjust = 0.5),
    axis.title = element_text(face = "bold")
  ) 

## Bests
plot_energy_consumption_vs_performance_bests <-
  ggplot(data = global_performance_no_SS %>% 
           filter(Flag %in% c("nb=auto pme=auto pmefft=auto bonded=auto update=auto",
                              "nb=gpu pme=gpu pmefft=gpu bonded=gpu update=gpu")
                  ),
         aes(x = ns.day_1e4atoms_AVG,
             y = Total_energy_J/1000,
         )
  ) +
  geom_line(linewidth = 0.5,
            color = "#257841FF"
              ) +
  geom_point(size = 2,
             color = "#257841FF",
  ) +
  facet_wrap(. ~ Flag, ncol = 3) +
  scale_y_continuous(name = "Energía consumida (kJ)",
                     limits = c(0,12),
                     breaks = seq(0, 12, 2),
                     expand = c(0,0)
  ) +
  scale_x_continuous(trans = "log10",
                     name = latex2exp::TeX(r'($Desempeño\,\left( \frac{ns/día}{10^4\,átomos} \right)$)'),
                     breaks = c(0.1, 1, 10, 100),
                     labels = c("0.1", "1", "10", "100"),
                     minor_breaks = c(seq(.1,1,.1), seq(1,10,1), seq(10,100,10)),
  ) +
  custom_theme +
  theme(
    legend.position = c(5/6, 1/10),
    strip.text = element_text(color = panel_dark_color, face = "bold", hjust = 0.5),
    axis.title = element_text(face = "bold")
  ) 
  

# Statistical modelling | Data preparation --------------------------------

## Auxiliary function to check if a flag was computed on CPU or GPU

one_hot_encode_GPU <- function(column, value) {
  # CPU returns 0
  # GPU returns 1
  ifelse(grepl(paste0(value, "=gpu"), column), 1, 0)
}

model_data <- 
  global_performance_no_SS %>% 
  # select(Atoms, Flag, Total_energy_J) %>% 
  filter(Flag != "nb=auto pme=auto pmefft=auto bonded=auto update=auto") %>% 
  mutate(nb_unloaded = one_hot_encode_GPU(Flag, "nb"),
         pme_unloaded = one_hot_encode_GPU(Flag, "pme"),
         pmefft_unloaded = one_hot_encode_GPU(Flag, "pmefft"),
         bonded_unloaded = one_hot_encode_GPU(Flag, "bonded"),
         update_unloaded = one_hot_encode_GPU(Flag, "update"),
         Total_energy_kJ = Total_energy_J/1000
         ) %>% 
  select(-Total_energy_J)

## Preliminary visualization
plot_model_data <- 
  ggplot(data = model_data,
         aes(x = Atoms,
             y = Total_energy_kJ,
             shape = Flag,
             color = Flag,
         )
  ) +
  geom_point(size = 1.25, stroke= 1.25) +
  scale_shape_manual(values= rep(1:7, len=14),
                     name = "Balance de carga",
  ) +
  paletteer::scale_color_paletteer_d("ggthemes::stata_s1color",
                                     name = "Balance de carga",
  ) +
  scale_y_continuous(name = "Energía consumida (kJ)",
                     trans = "identity",
                     limits = c(0,100),
                     breaks = seq(0,100,20),
                     minor_breaks = seq(0,100,10),
  ) +
  scale_x_continuous(name = "Tamaño del sistema (número de átomos)",
                     trans = "identity",
                     limits = c(1e4, biggest_system),
                     labels = scientific,
                     # breaks = c(1.2e4, 2e4, 4e4, 6e4, 1e5, 1.8e5),
                     breaks = c(1e4, 1e5, 2e5),
                     minor_breaks = seq(1e4,2.4e5,1e4),
  ) +
  custom_theme +
  theme(
    legend.position = "right",
    # panel.spacing = unit(1, "lines"),
    strip.text = element_text(color = panel_dark_color, face = "bold", hjust = 0.5),
    axis.title = element_text(face = "bold"),
  ) 


# Statistical modelling | Dependency on Atoms ---------------------------

## Auxiliary function for quickly plot models on top of data:
plot_model <- function(model, data, model_name) {
  plotted_model <- 
    ggplot(data = data) +
      geom_point(aes(x = Atoms,
                     y = Total_energy_kJ,
                     shape = Flag,
                     color = Flag,
                     ),
                 size = 1.25,
                 stroke= 1.25) +
      scale_shape_manual(values= rep(1:7, len=14),
                         name = "Balance de carga",
                         ) +
      paletteer::scale_color_paletteer_d("ggthemes::stata_s1color",
                                         name = "Balance de carga",
                                         ) +
      scale_y_continuous(name = "Energía consumida (kJ)",
                         trans = "identity",
                         limits = c(-5,100),
                         breaks = seq(0,100,20),
                         minor_breaks = seq(0,100,10),
                         ) +
      scale_x_continuous(name = "Tamaño del sistema (número de átomos)",
                         trans = "identity",
                         limits = c(1e4, biggest_system),
                         labels = scientific,
                         # breaks = c(1.2e4, 2e4, 4e4, 6e4, 1e5, 1.8e5),
                         breaks = c(1e4, 1e5, 2e5),
                         minor_breaks = seq(1e4,2.4e5,1e4),
      ) +
      labs(title = model_name,
           subtitle = model$call[2] %>% as.character()
      ) +
      custom_theme +
      theme(
        legend.position = "right",
        strip.text = element_text(color = panel_dark_color, face = "bold", hjust = 0.5),
        axis.title = element_text(face = "bold"),
        plot.subtitle = element_text(size = 9)
      ) +
      geom_line(aes(x = Atoms,
                    y = model$fitted.values,
                    group = Flag,
                    color = Flag),
                linewidth = 0.25,
                linetype = "dashed",
                )
  
  return(plotted_model)
}

### OBSERVATION: response variable depends both on Flags and number of Atoms.
### The flags are one-coded when they are unloaded to GPU.
### The number of atoms is a quantitative and continuous variable (dbl)


### Model 01: Response variable explained by atoms and flags (one-coded)
###           No interactions will be considered.
model_01 <- lm(data = model_data,
               formula = Total_energy_kJ ~ Atoms + 
               nb_unloaded + pme_unloaded + pmefft_unloaded +
                 bonded_unloaded + update_unloaded)

### Model 02: Response variable explained by atoms and flags (one-coded)
###           All possible interactions will be considered.
model_02 <- lm(data = model_data,
               formula = Total_energy_kJ ~ Atoms* 
                 nb_unloaded*pme_unloaded*pmefft_unloaded*
                 bonded_unloaded*update_unloaded)


plot_model(model_01, model_data, "Model 01")
plot_model(model_02, model_data, "Model 02")

### OBSERVATION: Model 02 fits almost perfectly the data.
### However, the interpretation of interaction terms between
### unloaded computations is not straightforward.

### Run further diagnostics for this model
summary(model_02)
gglm(model_02, theme = custom_theme)

### OBSERVATION: could Model 02 be improved by a polynomial term on Atoms?
model_03 <- lm(data = model_data,
               formula = Total_energy_kJ ~ poly(Atoms,3)* 
                 nb_unloaded*pme_unloaded*pmefft_unloaded*
                 bonded_unloaded*update_unloaded)

plot_model(model_03, model_data, "Model 03")
summary(model_03)
gglm(model_03, theme = custom_theme)

### OBSERVATION: using polynomials seem to improve the accuracy,
### but at the same time degrade the interpretability.

#### Increase the polynomial terms to 5
model_04 <- lm(data = model_data,
               formula = Total_energy_kJ ~ poly(Atoms,5)* 
                 nb_unloaded*pme_unloaded*pmefft_unloaded*
                 bonded_unloaded*update_unloaded)

plot_model(model_04, model_data, "Model 04")
summary(model_04)
gglm(model_04, theme = custom_theme)


### OBSERVATION: Model 04 seems to be the best one so far.
### This model will be simplified by removing the least important 
### explanatory variables.

model_04_ranked_coefficients <-  
  tibble(
    Variable = row.names(summary(model_04)$coef),
    Estimate = summary(model_04)$coef[,"Estimate"],
    p_value = summary(model_04)$coef[, "Pr(>|t|)"]
  ) %>% 
  arrange(p_value) %>% 
  mutate(Variable = parse_factor(Variable))


### Plot all explanatory variables, ranked by p-value
ggplot(data = model_04_ranked_coefficients,
       aes(x = p_value,
           y = Variable,
           fill = p_value
           )
       ) +
  geom_col() +
  scale_x_continuous(name = "p-valor",
                     limits = c(0,1),
                     breaks = seq(0, 1, 0.1),
                     minor_breaks = seq(0, 1, 0.05),
                     expand = c(0,0),
                     ) +
  scale_y_discrete(name = "Variable independiente",
                   limits = rev(levels(model_04_ranked_coefficients$Variable))
                   ) +
  custom_theme +
  scale_fill_paletteer_c("grDevices::Zissou 1", direction = 1) +
  theme(legend.position = "none")

extract_eq(model_04,
           swap_var_names = c("Atoms" = "A"),
           swap_subscript_names = c("nb_unloaded" = "nb",
                                    "pme_unloaded" = "pme",
                                    "pmefft_unloaded" = "pmefft",
                                    "bonded_unloaded" = "bonded",
                                    "update_unloaded" = "update"
           ),
)

rmserr(model_data$Total_energy_kJ, model_04$fitted.values)

### Zoom into best explanatory variables (i.e. p-value < 0.05)

model_04_best_variables <- 
  model_04_ranked_coefficients %>% 
  filter(p_value<=0.05) %>% 
  mutate(Variable = as.character(Variable)) %>% 
  mutate(Variable = parse_factor(Variable))

ggplot(data = model_04_best_variables,
       aes(x = p_value,
           y = Variable,
           fill = p_value,
           label = paste("Coefficiente:", Estimate)
           )
       ) +
  geom_col() +
  scale_x_continuous(name = "p-valor",
                     limits = c(0, .05),
                     breaks = seq(0, .05, .01),
                     minor_breaks = seq(0, .05, 0.005),
                     expand = c(0,0),
                     trans = "identity"
                     ) +
  scale_y_discrete(name = "Variable independiente",
                   limits = rev(levels(model_04_best_variables$Variable))
                   ) +
  custom_theme +
  scale_fill_paletteer_c("grDevices::Zissou 1", direction = 1) +
  geom_text(hjust = 0,
             size = 2.75,
             nudge_x = 1.5e-4,
             label.padding = unit(0.15, "lines")
             ) +
  theme(legend.position = "none")

### OBSERVATION: Model 04, although accurate, lacks interpretability.
### This is mainly due to the fact that using polynomials of Atoms
### is hard to interpret, specially when interacting with flags.


### New model proposed: no polynomials on Atoms, and all interactions only
### among flags.
model_05 <- lm(data = model_data,
               formula = Total_energy_kJ ~ Atoms+ 
                 nb_unloaded*pme_unloaded*pmefft_unloaded*
                 bonded_unloaded*update_unloaded)

#### VERY BAD MODEL
plot_model(model_05, model_data, "Model 05")
summary(model_05)
gglm(model_05, theme = custom_theme)


### Test polynomial of Atoms, but with no interactions with flags
model_06 <- lm(data = model_data,
               formula = Total_energy_kJ ~ poly(Atoms,5)+ 
                 nb_unloaded*pme_unloaded*pmefft_unloaded*
                 bonded_unloaded*update_unloaded)

plot_model(model_06, model_data, "Model 06")
summary(model_06)
gglm(model_06, theme = custom_theme)

#### VERY BAD MODEL, it seems obvious that interactions between Atoms
#### (as polynomials or not) with flags is mandatory. So, to keep it as 
#### interpretable as possible, let's fall back to model 02

### Falling back to Model 02, without polynomials of Atoms
model_02_ranked_coefficients <-
  tibble(
    Variable = row.names(summary(model_02)$coef),
    Estimate = summary(model_02)$coef[,"Estimate"],
    p_value = summary(model_02)$coef[, "Pr(>|t|)"]
  ) %>%
  arrange(p_value) %>%
  mutate(Variable = parse_factor(Variable))

### Plot all explanatory variables, ranked by p-value
ggplot(data = model_02_ranked_coefficients,
       aes(x = p_value,
           y = Variable,
           fill = p_value
           )
       ) +
  geom_col() +
  scale_x_continuous(name = "p-valor",
                     limits = c(0,1),
                     breaks = seq(0, 1, 0.1),
                     minor_breaks = seq(0, 1, 0.05),
                     expand = c(0,0),
                     ) +
  scale_y_discrete(name = "Variable independiente",
                   limits = rev(levels(model_02_ranked_coefficients$Variable))
                   ) +
  custom_theme +
  scale_fill_paletteer_c("grDevices::Zissou 1", direction = 1) +
  theme(legend.position = "none")

### Zoom into best explanatory variables (i.e. p-value < 0.05)\

summ(model_02)

model_02_best_variables <- 
  model_02_ranked_coefficients %>% 
  filter(p_value<=0.05) %>% 
  mutate(Variable = as.character(Variable)) %>% 
  mutate(Variable = parse_factor(Variable))

ggplot(data = model_02_best_variables,
       aes(x = p_value,
           y = Variable,
           fill = p_value,
           label = paste("Coefficiente:", signif(Estimate, 4))
           )
       ) +
  geom_col() +
  scale_x_continuous(name = "p-valor",
                     # limits = c(0, .05),
                     # breaks = seq(0, .05, .01),
                     # minor_breaks = seq(0, .05, 0.005),
                     expand = c(0,0),
                     trans = "identity"
                     ) +
  scale_y_discrete(name = "Variable independiente",
                   limits = rev(levels(model_02_best_variables$Variable))
                   ) +
  custom_theme +
  scale_fill_paletteer_c("grDevices::Zissou 1", direction = 1) +
  geom_text(hjust = 0,
            size = 2.75,
            nudge_x = 1e-5,
            label.padding = unit(0.15, "lines")
            ) +
  theme(legend.position = "none")

#### Peek into best predictors
model_02_best_variables
#### meaning that unloading pme causes the energy consumption to increase.

### OBSERVATION: New model to test: predictors will be the interactions of
### Atoms with a single flag at a time, and omitting and intercept.

model_07 <- lm(data = model_data,
               formula = Total_energy_kJ ~ 0 + Atoms +
                 Atoms:nb_unloaded + Atoms:pme_unloaded +
                 Atoms:pmefft_unloaded + Atoms:bonded_unloaded + 
                 Atoms:update_unloaded) 

#### It was also attempted to include the interactions among all the flags, but
#### this only made the model slightly worse regarding accuracy, and significatively
#### worse regarding interpretation.

plot_model(model_07, model_data, "Model 07") + labs (title = NULL, subtitle = NULL)
summ(model_07)
gglm(model_07, theme = custom_theme)

model_07_ranked_coefficients <-
  tibble(
    Variable = row.names(summary(model_07)$coef),
    Estimate = summary(model_07)$coef[,"Estimate"],
    p_value = summary(model_07)$coef[, "Pr(>|t|)"]
    ) %>%
  arrange(Estimate) %>%
  mutate(Variable = parse_factor(Variable))

extract_eq(model_07,
           swap_var_names = c("Atoms" = "A",
                              "nb_unloaded" = "nb",
                              "pme_unloaded" = "pme",
                              "pmefft_unloaded" = "pmefft",
                              "bonded_unloaded" = "bonded",
                              "update_unloaded" = "update"),
           swap_subscript_names = c("nb_unloaded" = "nb",
                                    "pme_unloaded" = "pme",
                                    "pmefft_unloaded" = "pmefft",
                                    "bonded_unloaded" = "bonded",
                                    "update_unloaded" = "update"
                                    ),
           greek_colors	= "red"
           )

rmserr(model_data$Total_energy_kJ, model_07$fitted.values)

# Statistical modelling | Dependency on flags -----------------------------

model_data_medians <- 
  model_data %>% group_by(Flag) %>% 
  summarise(Total_energy_kJ_median = median(Total_energy_kJ),
            ns.day_1e4atoms_median = median(ns.day_1e4atoms_AVG)) %>% 
  ungroup() %>% 
  mutate(Flag = as.character(Flag)) %>% 
  arrange(Total_energy_kJ_median) %>% 
  mutate(Flag = parse_factor(Flag,
                             ordered = TRUE
                             )
         )


plot_energy_vs_flags <- 
  ggplot() +
  geom_beeswarm(data = model_data,
                aes(x = Total_energy_kJ,
                    y = Flag,
                    # color = Atoms,
                    fill = Atoms,
                ),
                size = 2,
                shape = 21,
                alpha = 0.85,
                stroke = 0.6,
                cex = 1.5,
                ) +
  geom_point(data = model_data_medians,
             aes(x = Total_energy_kJ_median,
                 y = Flag),
             color = "darkred",
             shape = 8,
             size = 4) +
  scale_color_paletteer_c("grDevices::Zissou 1", 
                          direction = 1,
                          name = "Tamaño del sistema\n(número de átomos)"
                          ) +
  scale_fill_paletteer_c("grDevices::Zissou 1", 
                         direction = 1,
                         name = "Tamaño del sistema\n(número de átomos)"
                         ) +
  scale_x_continuous(name = "Energía consumida (kJ)",
                     trans = "log10",
                     breaks = c(1, 10, 100),
                     labels = c(1, 10, 100),
                     minor_breaks = c(seq(1,10,1),seq(10,100,10))
                     ) +
  scale_y_discrete(name = "Balance de carga",
                   limits = rev(levels(model_data_medians$Flag))
                   ) +
  custom_theme +
  labs(caption = "*La métrica de tendencia central (   ) es la mediana de cada balance de carga.") +
  theme(
    axis.title = element_text(face = "bold")
  )







