local particles = script.Parent.Particles2
particles.Lifetime = NumberRange.new(1.2, 2.0)

while wait(0.001) do
	particles:Emit(60)
end