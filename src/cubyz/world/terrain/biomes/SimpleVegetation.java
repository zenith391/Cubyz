package cubyz.world.terrain.biomes;

import java.util.Random;

import cubyz.api.CubyzRegistries;
import cubyz.api.Resource;
import cubyz.utils.json.JsonObject;
import cubyz.world.Chunk;
import cubyz.world.blocks.Block;
import cubyz.world.terrain.MapFragment;

/**
 * One position vegetation, like grass or cactus.
 */

public class SimpleVegetation extends StructureModel {
	Block block;
	int height0, deltaHeight;

	public SimpleVegetation() {
		super(new Resource("cubyz", "simple_vegetation"), 0);
		this.block = null;
		height0 = 0;
		deltaHeight = 0;
	}
	public SimpleVegetation(JsonObject json) {
		super(new Resource("cubyz", "simple_vegetation"), json.getFloat("chance", 0.5f));
		this.block = CubyzRegistries.BLOCK_REGISTRY.getByID(json.getString("block", "cubyz:grass"));
		height0 = json.getInt("height", 1);
		deltaHeight = json.getInt("height_variation", 0);
	}
	
	@Override
	public void generate(int x, int z, int h, Chunk chunk, MapFragment map, Random rand) {
		if(chunk.getVoxelSize() > 2 && (x / chunk.getVoxelSize() * chunk.getVoxelSize() != x || z / chunk.getVoxelSize() * chunk.getVoxelSize() != z)) return;
		int y = chunk.getWorldY();
		if(chunk.liesInChunk(x, h-y, z)) {
			int height = height0;
			if(deltaHeight != 0)
				height += rand.nextInt(deltaHeight);
			for(int py = chunk.startIndex(h); py < h + height; py += chunk.getVoxelSize()) {
				if(chunk.liesInChunk(x, py-y, z)) {
					chunk.updateBlockIfDegradable(x, py-y, z, block);
				}
			}
		}
	}

	@Override
	public StructureModel loadStructureModel(JsonObject json) {
		return new SimpleVegetation(json);
	}
}
