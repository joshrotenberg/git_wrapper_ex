import AgentWorkshop.Workshop

IO.puts("""
\e[36mWorkshop loaded.\e[0m
""")

if File.exists?(".workshop.exs") do
  AgentWorkshop.Workshop.load()
end
