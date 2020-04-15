package io.cubyz.world;

import org.joml.Vector4f;

/*
 * STELLAR TORUSES !!1!!!
 */
public abstract class StellarTorus {
	protected int season; // 0=Spring, 1=Summer, 2=Autumn, 3=Winter
	protected World world;
	protected StellarTorus orbitalParent;
	protected String name;
	protected float distance, angle; // the relative angle and distance to the orbital parent.
	// if this torus doesn't have an orbital parent, use the following variables:
	protected float absX, absY; // absolute positions if the above condition is true
	
	public int DAYCYCLE;

	public abstract void cleanup();
	
	public abstract float getGlobalLighting();
	public abstract Vector4f getAtmosphereColor(); // = clear color in practice
	
	public abstract long getLocalSeed();
	
	public TorusSurface getSurface() {
		return null;
	}
	
	public StellarTorus getOrbitalParent() {
		return orbitalParent;
	}
	
	public abstract boolean hasSurface();

	public int getAnd() {
		return -1; // WorldAnd of maximum supported world size.
	}
	
	public int getSeason() {
		return season;
	}
	
	public void setName(String name) {
		this.name = name;
	}
	
	public String getName() {
		return name;
	}
	
	public World getWorld() {
		return world;
	}
	
	public void update() {}
}
