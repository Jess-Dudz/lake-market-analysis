library(tidycensus)
library(tidyverse)
library(scales)
library(writexl)

# --- 0. Setup ---
# Replace 'YOUR_KEY_HERE' with your actual API key, 
# or use Sys.getenv("CENSUS_API_KEY") if stored in your .Renviron
# census_api_key("YOUR_KEY_HERE")

# --- 1. Pull Data ---
service_area_list <- list(
  "MO" = c("Taney", "Stone", "Barry", "Hickory", "Polk", "Ozark", "Cedar", "Dade"),
  "AR" = c("Benton", "Carroll")
)

# Fetching 2022 5-year ACS data (reliable stable estimates)
raw_census_data <- map_dfr(names(service_area_list), function(st) {
  get_acs(
    geography = "tract",
    variables = c(income = "B19013_001", home_val = "B25077_001"),
    state = st,
    county = service_area_list[[st]],
    year = 2022,
    output = "wide"
  )
})

# --- 2. Refine, Clean, and Filter ---
lake_analysis_final <- raw_census_data %>%
  mutate(
    # Identify state from the NAME string
    state_name = case_when(
      str_detect(NAME, "Missouri") ~ "Missouri",
      str_detect(NAME, "Arkansas") ~ "Arkansas",
      TRUE ~ "Other"
    ),
    # Cluster counties into specific Lake Regions
    lake_region = case_when(
      str_detect(NAME, "Benton|Carroll") ~ "Beaver Lake",
      str_detect(NAME, "Taney|Stone|Barry") ~ "Table Rock / Bull Shoals",
      str_detect(NAME, "Hickory|Polk") ~ "Pomme de Terre",
      str_detect(NAME, "Cedar|Dade") ~ "Stockton Lake",
      TRUE ~ "DELETE"
    )
  ) %>%
  filter(lake_region != "DELETE") %>%
  rename(income = incomeE, home_val = home_valE) %>%
  mutate(
    # MARKET HOTNESS FORMULA:
    # We weight income per $1k and home value per $5k to identify premium targets
    market_hotness = (income / 1000) + (home_val / 5000),
    suggested_budget_pct = (market_hotness / sum(market_hotness, na.rm = TRUE)) * 100
  )

# --- 3. Create Summary for Plotting ---
lake_summary <- lake_analysis_final %>%
  group_by(lake_region, state_name) %>%
  summarise(total_budget_pct = sum(suggested_budget_pct, na.rm = TRUE), .groups = "drop")

# --- 4. Visualization ---
market_plot <- ggplot(lake_summary, 
                      aes(x = reorder(lake_region, total_budget_pct), 
                          y = total_budget_pct, 
                          fill = state_name)) +
  # Using linewidth instead of size to avoid warnings
  geom_col(width = 0.7, color = "white", linewidth = 0.5) +
  geom_text(aes(label = paste0(round(total_budget_pct, 1), "%")), 
            hjust = -0.2, size = 5, fontface = "bold", color = "grey20") +
  coord_flip() +
  scale_y_continuous(labels = label_percent(scale = 1), 
                     expand = expansion(mult = c(0, .2))) +
  scale_fill_manual(values = c("Missouri" = "#003366", "Arkansas" = "#990000")) + 
  labs(
    title = "Market Priority Analysis by Lake Region",
    subtitle = "Budget allocation based on Median Income and Property Value Index",
    caption = "Source: US Census Bureau ACS 5-Year Estimates",
    x = NULL,
    y = "Recommended % of Marketing Effort",
    fill = "State"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    plot.title = element_text(face = "bold", size = 18),
    panel.grid.major.y = element_blank(),
    legend.position = "bottom"
  )

# Display Plot
print(market_plot)

# --- 5. Exporting Outputs ---
# Save the plot
ggsave("lake_market_priority_plot.png", plot = market_plot, width = 10, height = 6, dpi = 300)

# Save the high-value target neighborhoods
target_neighborhoods <- lake_analysis_final %>%
  arrange(desc(market_hotness)) %>%
  slice_head(n = 10) %>%
  select(lake_region, NAME, income, home_val)

write_xlsx(target_neighborhoods, "target_neighborhood_analysis.xlsx")