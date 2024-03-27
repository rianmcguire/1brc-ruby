require "standard/rake"
require "rake/extensiontask"

Rake::ExtensionTask.new("io_buffer_hacks")
Rake::ExtensionTask.new("io_buffer_reader")

task default: [:compile, "slides.html", "notes.txt"]

file "slides.html" => ["slides.md", "fig2.svg", "asciinema-player.js", "asciinema-player.css"] do |t|
    sh "node_modules/.bin/marp --html #{t.prerequisites.first} -o #{t.name}"
end

file "notes.txt" => ["slides.md"] do |t|
    sh "node_modules/.bin/marp --notes #{t.prerequisites.first} -o #{t.name}"
end

file "asciinema-player.js" => "node_modules/asciinema-player/dist/bundle/asciinema-player.js" do |t|
    cp t.prerequisites.first, t.name
end

file "asciinema-player.css" => "node_modules/asciinema-player/dist/bundle/asciinema-player.css" do |t|
    cp t.prerequisites.first, t.name
end

task :server => ["fig2.svg"] do
    sh "node_modules/.bin/marp --server --html ."
end

file "fig2.svg" => ["charts.py", *Dir.glob("*.csv")] do |t|
    sh "./charts.py"
end
