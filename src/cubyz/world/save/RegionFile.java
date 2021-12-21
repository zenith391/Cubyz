package cubyz.world.save;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Arrays;
import java.util.zip.DataFormatException;
import java.util.zip.Deflater;
import java.util.zip.Inflater;

import cubyz.client.Cubyz;
import cubyz.utils.Logger;
import cubyz.utils.math.Bits;
import cubyz.world.ChunkData;
import cubyz.world.NormalChunk;
import cubyz.world.ServerWorld;

/**
 * Multiple chunks are bundled up in regions to reduce disk reads/writes.
 */
public class RegionFile extends ChunkData {
	private static final ThreadLocal<byte[]> threadLocalInputBuffer = new ThreadLocal<byte[]>() {
		@Override
		public byte[] initialValue() {
			return new byte[4*NormalChunk.chunkSize*NormalChunk.chunkSize*NormalChunk.chunkSize];
		}
	};
	private static final ThreadLocal<byte[]> threadLocalOutputBuffer = new ThreadLocal<byte[]>() {
		@Override
		public byte[] initialValue() {
			return new byte[4*NormalChunk.chunkSize*NormalChunk.chunkSize*NormalChunk.chunkSize];
		}
	};
	public static final int REGION_SHIFT = 2;
	public static final int REGION_SIZE = 1 << REGION_SHIFT;
	public static final int WORLD_SHIFT = REGION_SHIFT + NormalChunk.chunkShift;
	public static final int WORLD_MASK = (1 << WORLD_SHIFT) - 1;
	private byte[] data = new byte[0];
	private boolean[] occupancy = new boolean[REGION_SIZE*REGION_SIZE*REGION_SIZE];
	private int[] startingIndices = new int[REGION_SIZE*REGION_SIZE*REGION_SIZE + 1];
	private boolean wasChanged = false;
	public boolean storeOnChange = false;

	public RegionFile(ServerWorld world, int wx, int wy, int wz, int voxelSize) {
		super(wx, wy, wz, voxelSize);
		// Load data from file:
		File file = new File("saves/"+world.getName()+"/"+voxelSize+"/"+wx+"/"+wy+"/"+wz+".region");
		if(!file.exists()) {
			return;
		}
		try (InputStream in = new FileInputStream(file)) {
			byte[] data = in.readAllBytes();
			if(data.length < 4) return;
			
			int offset = 0;
			int compressor = Bits.getInt(data, offset);
			offset += 4;
			if(compressor != 0) {
				Logger.error("Unknown compression algorithm "+compressor+" for save file \""+file.getAbsolutePath()+"\".");
				return;
			}
			long occupancyLong = Bits.getLong(data, offset);
			offset += 8;
			int index = -1;
			for(int i = 0; i < occupancy.length; i++) {
				occupancy[i] = (occupancyLong & 1l << i) != 0;
				if(occupancy[i]) {
					startingIndices[i] = Bits.getInt(data, offset);
					for(index++; index < i; index++) {
						startingIndices[index] = startingIndices[i];
					}
					offset += 4;
				} else if(i == 0) {
					startingIndices[i] = 0;
				} else {
					startingIndices[i] = startingIndices[i - 1];
				}
			}
			
			this.data = Arrays.copyOfRange(data, offset, data.length);
			for(index++; index < startingIndices.length; index++) {
				startingIndices[index] = this.data.length;
			}
		} catch (IOException e) {
			Logger.error("Unable to load chunk resources.");
			Logger.error(e);
		}
	}
	
	private int getChunkIndex(NormalChunk ch) {
		int chunkIndex = (ch.wx - wx) >> NormalChunk.chunkShift;
		chunkIndex = chunkIndex << REGION_SHIFT | (ch.wy - wy) >> NormalChunk.chunkShift;
		chunkIndex = chunkIndex << REGION_SHIFT | (ch.wz - wz) >> NormalChunk.chunkShift;
		return chunkIndex;
	}
	
	public boolean loadChunk(NormalChunk ch) {
		int chunkIndex = getChunkIndex(ch);
		
		byte[] input = threadLocalInputBuffer.get();
		byte[] output = threadLocalOutputBuffer.get();
		int inputLength = startingIndices[chunkIndex + 1] - startingIndices[chunkIndex];
		if(inputLength == 0) return false;
		System.arraycopy(data, startingIndices[chunkIndex], input, 0, inputLength);
		
		Inflater decompresser = new Inflater();
		decompresser.setInput(input, 0, inputLength);
		try {
			decompresser.inflate(output);
		} catch (DataFormatException e) {
			Logger.error("Unable to load chunk data. Corrupt chunk file "+this.toString());
			Logger.error(e);
			return false;
		}
		decompresser.end();
		
		ch.loadFrom(output);
		return true;
	}
	
	public void saveChunk(NormalChunk ch) {
		synchronized(this) {
			wasChanged = true;
			int chunkIndex = getChunkIndex(ch);
			byte[] input = threadLocalInputBuffer.get();
			byte[] output = threadLocalOutputBuffer.get();
			ch.saveTo(input);
			
			Deflater compressor = new Deflater();
			compressor.setInput(input);
			compressor.finish();
			int dataLength = compressor.deflate(output);
			
			while(!compressor.needsInput()) { // The buffer was too small. Switching to a bigger buffer.
				output = Arrays.copyOf(output, output.length*2);
				dataLength += compressor.deflate(output, output.length/2, output.length/2);
			}
			compressor.end();
			
			int dataInsertionIndex = startingIndices[chunkIndex];
			int oldDataLength = startingIndices[chunkIndex + 1] - dataInsertionIndex;
			byte[] newData = new byte[data.length + dataLength - oldDataLength];
			System.arraycopy(data, 0, newData, 0, dataInsertionIndex);
			System.arraycopy(output, 0, newData, dataInsertionIndex, dataLength);
			System.arraycopy(data, startingIndices[chunkIndex + 1], newData, dataInsertionIndex + dataLength, data.length - startingIndices[chunkIndex + 1]);
			data = newData;
			
			for(int i = chunkIndex + 1; i < startingIndices.length; i++) {
				startingIndices[i] += dataLength - oldDataLength;
			}
			if(oldDataLength == 0) {
				// This chunks wasn't in the list before:
				occupancy[chunkIndex] = true;
			}
		}
		if(storeOnChange)
			store();
	}
	
	public void store() {
		synchronized(this) {
			if(!wasChanged) return; // No need to save it.
			File file = new File("saves/"+Cubyz.world.getName()+"/"+voxelSize+"/"+wx+"/"+wy+"/"+wz+".region");
			file.getParentFile().mkdirs();
			try (BufferedOutputStream out = new BufferedOutputStream(new FileOutputStream(file))) {
				long occupancyLong = 0;
				int numberOfChunks = 0;
				for(int i = 0; i < occupancy.length; i++) {
					if(occupancy[i]) {
						occupancyLong |= 1l << i;
						numberOfChunks++;
					}
				}
				
				byte[] metaData = new byte[4 + 8 + 4*numberOfChunks];
				int offset = 0;
				Bits.putInt(metaData, offset, 0); // compressor version
				offset += 4;
				Bits.putLong(metaData, offset, occupancyLong);
				offset += 8;
				for(int i = 0; i < occupancy.length; i++) {
					if(occupancy[i]) {
						Bits.putInt(metaData, offset, startingIndices[i]);
						offset += 4;
					}
				}
				
				out.write(metaData);
				out.write(data);
			} catch (IOException e) {
				Logger.error("Unable to store chunk resources.");
				Logger.error(e);
			}
			wasChanged = false;
		}
	}

	/**
	 * Converts the world coordinate to the coordinate of the region file it lies in.
	 * @param worldCoordinate
	 * @return
	 */
	public static int findCoordinate(int worldCoordinate) {
		return worldCoordinate & ~WORLD_MASK;
	}
	
	@Override
	public void finalize() {
		if(wasChanged) {
			Logger.crash(wx+" "+wy+" "+wz);
			System.exit(1);
		}
	}
}
