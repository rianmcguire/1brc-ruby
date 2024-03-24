require "standard/rake"
require "rake/extensiontask"

Rake::ExtensionTask.new("io_buffer_hacks")
Rake::ExtensionTask.new("io_buffer_reader")

task default: [:compile, "slides.html"]

file "slides.html" => ["slides.md", "fig2.svg"] do |t|
    sh "node_modules/.bin/marp --html #{t.prerequisites.first} -o #{t.name}"
end

task :server => ["fig2.svg"] do
    sh "node_modules/.bin/marp --server --html ."
end

file "fig2.svg" => ["charts.py", *Dir.glob("*.csv")] do |t|
    sh "./charts.py"
end
