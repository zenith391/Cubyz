package cubyz.world.terrain.biomes;

import java.util.Random;

import cubyz.api.CubyzRegistries;
import cubyz.world.Chunk;
import cubyz.world.blocks.Block;

/**
 * Stores the vertical ground structure of a biome from top to bottom.<br>
 */

public class BlockStructure {
	private final BlockStack[] structure;
	public BlockStructure(BlockStack ... blocks) {
		structure = blocks;
	}
	public BlockStructure(String ... blocks) {
		structure = new BlockStack[blocks.length];
		for(int i = 0; i < blocks.length; i++) {
			String[] parts = blocks[i].trim().split("\\s+");
			int min = 1;
			int max = 1;
			String blockString = parts[0];
			if(parts.length == 2) {
				min = max = Integer.parseInt(parts[0]);
				blockString = parts[1];
			} else if(parts.length == 4 && parts[1].equalsIgnoreCase("to")) {
				min = Integer.parseInt(parts[0]);
				max = Integer.parseInt(parts[2]);
				blockString = parts[3];
			}
			Block block = CubyzRegistries.BLOCK_REGISTRY.getByID(blockString);
			structure[i] = new BlockStructure.BlockStack(block, min, max);
		}
	}
	
	public int addSubTerranian(Chunk chunk, int depth, int x, int z, int highResDepth, Random rand) {
		int startingDepth = depth;
		for(int i = 0; i < structure.length; i++) {
			int total = structure[i].min + rand.nextInt(1 + structure[i].max - structure[i].min);
			for(int j = 0; j < total; j++) {
				byte data = structure[i].block.mode.getNaturalStandard();
				if(i == 0 && j == 0 && structure[i].block.mode.getRegistryID().toString().equals("cubyz:stackable")) {
					data = (byte)highResDepth;
				}
				if(chunk.liesInChunk(x, depth - chunk.getWorldY(), z)) {
					chunk.updateBlock(x, depth - chunk.getWorldY(), z, structure[i].block, data);
				}
				depth -= chunk.getVoxelSize();
			}
		}
		if(depth == startingDepth) return depth;
		return depth + 1;
	}
	
	public static class BlockStack {
		private final Block block;
		private final int min;
		private final int max;
		public BlockStack(Block block, int min, int max) {
			this.block = block;
			this.min = min;
			this.max = max;
		}
	}
}
